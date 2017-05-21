%%
%% This is the version of rabbit_rpc_client from RabbitMQ erlang client.
%%
%%
-module(webmqx_rpc_worker).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("webmqx.hrl").

-behaviour(gen_server2).

-export([start_link/1, stop/1]).
-export([rpc/5, rpc/6, consistent_publish/4]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([flush_routing_ring/2]).

-record(state, {
				vhost = webmqx_util:env_vhost(), 
				connection,	
				rabbit_channel,
                reply_queue,
				n,
				routing_cache = dict:new(),
				consistent_req_queues = gb_sets:new(),
                continuations = dict:new(),
                correlation_id = 0}).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(start_link/1 :: (non_neg_integer()) -> rabbit_types::ok(pid())). 
-spec(rpc/5 :: ('sync', pid(), term(), binary(), binary()) -> rabbit_types::ok(binary()) | undefined).
-spec(rpc/6 :: ('async', pid(), non_neg_integer(), term(),  binary(), binary()) -> 'ok').
-spec(consistent_publish/4 :: (pid(), term(), binary(), binary()) -> rabbit_types::ok_or_error(any())).

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

%% Called by webmqx_consistent_req_broker.
rpc(async, WorkerPid, SeqId, ClientIP, Path, Payload) ->
    gen_server2:cast(WorkerPid, {rpc_async, {self(), SeqId}, ClientIP, Path, Payload}).

%% Called by webmqx_http_handler.
consistent_publish(WorkerPid, ClientIP, Path, Payload) ->
	gen_server2:call(WorkerPid, {consistent_publish, ClientIP, Path, Payload}, infinity).

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

handle_call({consistent_publish, ClientIP, Path, Payload}, _From, State) ->
	{R, NewState} = internal_consistent_publish(ClientIP, Path, Payload, State),
	{reply, R, NewState};

handle_call({rpc_sync, ClientIP, Path, Payload}, From, State) ->
	NewState = internal_rpc_publish(ClientIP, Path, Payload, _From = {rpc_sync, From}, State),
	{noreply, NewState}.

handle_cast({rpc_async, {From, SeqId}, ClientIP, Path, Payload}, State) -> 
	NewState = internal_rpc_publish(ClientIP, Path, Payload, _From = {rpc_async, {From, SeqId}}, State),
	{noreply, NewState};

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
             Msg = #amqp_msg{props = #'P_basic'{correlation_id = Id},
                       payload = Payload}},
            State = #state{continuations = Conts}) ->
	case dict:fetch(Id, Conts) of
		{rpc_sync, FromPid} ->	
			gen_server2:reply(FromPid, {ok, Payload});
		{rpc_async, {FromPid, SeqId}} ->
			gen_server2:cast(FromPid, {rpc_ok, SeqId, {ok, Payload}})
	end,
    {noreply, State#state{continuations = dict:erase(Id, Conts) }};

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

internal_rpc_publish(ClientIP, Path, Payload, From,
        State = #state{rabbit_channel = {_ChannelRef, Channel},
                       reply_queue = Q,
					   routing_cache = RoutingCache,
                       correlation_id = CorrelationId,
                       continuations = Continuations}) ->
    EncodedCorrelationId = base64:encode(<<CorrelationId:64>>),
    Props = #'P_basic'{correlation_id = EncodedCorrelationId,
                       content_type = <<"application/octet-stream">>,
                       reply_to = Q},

	{ok, Ring, RoutingCache1} =  get_ring(webmqx_util:path_to_words(Path), RoutingCache),
	case Ring of
		undefined ->
			case From of
				{rpc_sync, FromPid} ->	
					gen_server2:reply(FromPid, undefined);
				{rpc_async, {FromPid, SeqId}} ->
					gen_server2:cast(FromPid, {rpc_ok, SeqId, undefined})
			end;
		_ ->
			#resource{name = QueueName} = concha:lookup(ClientIP, Ring),
			Publish = #'basic.publish'{exchange = <<"">>, 
                               routing_key = QueueName,
                               mandatory = true},
			amqp_channel:call(Channel, Publish, #amqp_msg{props = Props,
                                                  payload = Payload})
	end,

    State#state{correlation_id = CorrelationId + 1,
				routing_cache = RoutingCache1,
                continuations = dict:store(EncodedCorrelationId, From, Continuations)}.

internal_consistent_publish(ClientIP, Path, Payload,
        State = #state{vhost = VHost,
						rabbit_channel = {_ChannelRef, Channel}, 
						consistent_req_queues = ConsReqQueues}) ->
	{IsAbsent, NewState} = 
	case gb_sets:is_element(Path, ConsReqQueues) of
		true -> {true, State};
		false ->
			Queue =  #resource{virtual_host = VHost, kind = queue, name = Path},
			case rabbit_amqqueue:with(Queue, fun(_) -> ok end) of
				ok -> 
					{true, State#state{consistent_req_queues = gb_sets:add(Path, ConsReqQueues)}};
				R ->
					error_logger:info_msg("no this queue named the path ~p ~p~n", [Path, R]),
					{false, State}
			end
	end,

	case IsAbsent of
		true ->
			Publish = #'basic.publish'{exchange = <<"">>,
										routing_key = Path,
										mandatory = true},

			case amqp_channel:call(Channel, Publish, #amqp_msg{payload = Payload, 
															   props   = #'P_basic'{correlation_id = ClientIP}}) of
				ok ->
					{ok, NewState};
				Error ->
					{Error, NewState}	
			end;
		false ->
			{not_found, State} 
	end.

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
	Queues = rabbit_exchange_type_webmqx:fetch_routing_queues(_VHost = <<"/">>, ?EXCHANGE_WEBMQX, WordsOfPath),
	case Queues of
		[] ->
			NowTimeStamp = now_timestamp_counter(),
			{ok, undefined, dict:store({key, WordsOfPath}, {none, NowTimeStamp}, RoutingCache)}; 
		[_|_] ->
			Ring = concha:new(Queues),
			{ok, Ring,  dict:store({key, WordsOfPath}, Ring, RoutingCache)}
	end.
