%%
%% This is the version of rabbit_rpc_client from RabbitMQ erlang client.
%%
%%
-module(webmqx_rpc_worker).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("webmqx.hrl").

-behaviour(gen_server2).

-export([start_link/1, stop/1]).
-export([rpc/5]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([flush_routing_ring/2]).

-record(state, {
               vhost = webmqx_util:env_vhost(), 
               connection,     
               rabbit_channel,
               reply_queue,
               n,
               routing_cache = dict:new()}).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(start_link/1 :: (non_neg_integer()) -> rabbit_types::ok(pid())). 
-spec(rpc/5 :: ('sync', pid(), term(), binary(), binary()) -> rabbit_types::ok(binary()) | undefined).

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported functions
%%%

start_link(N) ->
    {ok, Pid} = gen_server2:start_link(?MODULE, [N], []),
    {ok, Pid}.

%% Called by webmqx_http_handler.
rpc(sync, WorkerPid, ClientIP, Path, Payload) ->
    gen_server2:call(WorkerPid, {rpc_sync, ClientIP, Path, Payload}, infinity).

flush_routing_ring(Pid, WordsOfPath) ->
    gen_server:cast(Pid, {flush_routing_ring, WordsOfPath}).

stop(Pid) ->
    gen_server2:call(Pid, stop, infinity).

%%%
%%% Callbacks of gen_server
%%%

init([N]) ->
    process_flag(trap_exit, true),

    Username = webmqx_util:env_username(),
    Password = webmqx_util:env_password(),
    VHost = webmqx_util:env_vhost(),

    {ok, Connection} = amqp_connection:start(#amqp_params_direct{username = Username,
                                                                    password = Password,
                                                                    virtual_host = VHost}),

    {ok, Channel} = amqp_connection:open_channel(
                                            Connection, {amqp_direct_consumer, [self()]}),
    ConnectionRef = erlang:monitor(process, Connection),
    ChannelRef = erlang:monitor(process, Channel),
    ExchangeDeclare = #'exchange.declare'{exchange = ?EXCHANGE_WEBMQX, 
                                            type = ?EXCHANGE_WEBMQX_TYPE},
    #'exchange.declare_ok'{} = amqp_channel:call(Channel, ExchangeDeclare),

    InitialState = #state{
                        connection  = {ConnectionRef, Connection},
                        rabbit_channel     = {ChannelRef, Channel},
                        reply_queue = <<"amq.rabbitmq.reply-to">>
                    },

    State = setup_reply_queue(InitialState),
    setup_consumer(State),
        
    webmqx_rpc_worker_manager:join(N, self()),
    {ok, State#state{n = N}}.

terminate(_Reason, #state{connection = {ConnectionRef, Connection}, 
                                                        rabbit_channel = {ChannelRef, Channel}}) ->
    erlang:demonitor(ConnectionRef),
    erlang:demonitor(ChannelRef),

    amqp_channel:close(Channel),
    amqp_direct_connection:server_close(Connection, <<"404">>, <<"close">>),
    amqp_connection:close(Connection),
    ok.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call({rpc_sync, ClientIP, Path, Payload}, From, State) ->
    NewState = internal_rpc_publish(ClientIP, Path, Payload, From, State),
    {noreply, NewState}.

handle_cast({flush_routing_ring, WordsOfPath}, State = #state{routing_cache = RoutingCache}) ->
    {ok, _, RoutingCache1} = fetch_rabbit_queues(WordsOfPath, RoutingCache),
    {noreply, State#state{routing_cache = RoutingCache1}}; 

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({#'basic.consume'{}, _Pid}, State) ->
    {noreply, State};

handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

handle_info(#'basic.cancel'{}, State) ->
    {noreply, State};

handle_info(#'basic.cancel_ok'{}, State) ->
    {stop, normal, State};

%% Message from queue of application server.
handle_info({#'basic.deliver'{},
                _Msg = #amqp_msg{props = #'P_basic'{correlation_id = FromBin},
                        payload = Payload}},
                State) ->
    %FromPid = list_to_pid(binary_to_list(base64:decode(Pid64))),
    From = binary_to_term(base64:decode(FromBin)),
    gen_server2:reply(From, {ok, Payload}),
    {noreply, State};

handle_info({'EXIT', _Pid, Reason}, State) ->
    {stop, Reason, State};

handle_info({'DOWN', _MRef, process, _Pid, Reason}, State) ->
    {stop, {error, Reason}, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%
%%% Local functions
%%%

setup_reply_queue(State = #state{rabbit_channel = {_Ref, Channel}, reply_queue = Q}) ->
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue = Q}),
    State.

setup_consumer(#state{rabbit_channel = {_Ref, Channel}, reply_queue = Q}) ->
    #'basic.consume_ok'{} =
                amqp_channel:call(Channel, #'basic.consume'{queue = Q, no_ack = true}).

internal_rpc_publish(ClientIP, Path, Payload, From = {_FromPid, _Ref},
                        State = #state{rabbit_channel = {_ChannelRef, Channel},
                                        reply_queue = Q,
                                        routing_cache = RoutingCache}) ->
    %Props = #'P_basic'{correlation_id = base64:encode(pid_to_list(FromPid)),
    Props = #'P_basic'{correlation_id = base64:encode(term_to_binary(From)),
                        content_type = <<"application/octet-stream">>,
                        reply_to = Q},

    {ok, Ring, RoutingCache1} =  get_ring(webmqx_util:path_to_words(Path), RoutingCache),
    %error_logger:info_msg(" Ring : ~p RoutingCache1 : ~p", [Ring, RoutingCache1]),
    case Ring of
        undefined ->
            gen_server2:reply(From, undefined);
         _ ->
            #resource{name = QueueName} = concha:lookup(ClientIP, Ring),
            Publish = #'basic.publish'{exchange = <<"">>, 
                                        routing_key = QueueName,
                                        mandatory = true},
            amqp_channel:call(Channel, Publish, #amqp_msg{props = Props,
                                payload = Payload})
    end,

    State#state{routing_cache = RoutingCache1}.

now_timestamp_counter() ->
    {{_NowYear, _NowMonth, _NowDay},{NowHour, NowMinute, NowSecond}} = calendar:now_to_local_time(os:timestamp()),
    (NowHour*3600 + NowMinute*60 + NowSecond).

get_ring(WordsOfPath, RoutingCache) ->
    case dict:find({key, WordsOfPath}, RoutingCache) of
        {ok, {none, LastTryStamp}} -> 
            NowTimeStamp = now_timestamp_counter(),
            if
                (NowTimeStamp < LastTryStamp) orelse ((NowTimeStamp - LastTryStamp) > 10) ->
                    fetch_rabbit_queues(WordsOfPath, RoutingCache);
                true -> 
                    {ok, undefined, RoutingCache}   
            end;
        {ok, Ring} ->
            {ok, Ring, RoutingCache};
        error ->
            fetch_rabbit_queues(WordsOfPath, RoutingCache)
    end.

fetch_rabbit_queues(WordsOfPath, RoutingCache) ->
    WR = lists:reverse(WordsOfPath),
    fetch_rabbit_queues1(WR, RoutingCache, WR, undefined). 

fetch_rabbit_queues1(_, RoutingCache, Key, Queues = [_|_]) -> 
    Ring = concha:new(Queues), 
    {ok, Ring,  dict:store({key, Key}, Ring, RoutingCache)};

fetch_rabbit_queues1([], RoutingCache, Key, undefined) -> 
    NowTimeStamp = now_timestamp_counter(),
    {ok, undefined, dict:store({key, Key}, {none, NowTimeStamp}, RoutingCache)}; 

fetch_rabbit_queues1(WR = [_|WRLeft], RoutingCache, _, undefined) ->
    WordsOfPath = lists:reverse(WR),
    Queues = rabbit_exchange_type_webmqx:fetch_routing_queues(_VHost = <<"/">>, ?EXCHANGE_WEBMQX, WordsOfPath),
    %error_logger:info_msg(" WR : ~p  WordsOfPath: ~p Queues : ~p", [WR, WordsOfPath, Queues]),
    case Queues of
        [] ->
            fetch_rabbit_queues1(WRLeft, RoutingCache, WordsOfPath, undefined);
        [_|_] ->
            fetch_rabbit_queues1(WRLeft, RoutingCache, WordsOfPath, Queues)
    end.
