-module(webmqx_rpc_worker).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("webmqx.hrl").

-behaviour(gen_server2).

-export([start_link/1, stop/1]).
-export([rpc/4, rpc/5, normal_publish/3]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).

-record(state, {
				connection,	
				rabbit_channel,
                reply_queue,
				n,
				consistent_req_queues = gb_sets:new(),
                continuations = dict:new(),
                correlation_id = 0}).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(start_link/1 :: (non_neg_integer()) -> rabbit_types::ok(pid())). 
-spec(rpc/4 :: ('sync', pid(), binary(), binary()) -> rabbit_types::ok(binary()) | undefined).
-spec(rpc/5 :: ('async', pid(), non_neg_integer(), binary(), binary()) -> 'ok').
-spec(normal_publish/3 :: (pid(), binary(), binary()) -> rabbit_types::ok_or_error(any())).

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported functions
%%%

start_link(N) ->
    {ok, Pid} = gen_server2:start_link(?MODULE, [N], []),
	{ok, Pid}.

%% Called by webmqx_http_handler.
rpc(sync, WorkerPid, Path, Payload) ->
    gen_server2:call(WorkerPid, {rpc_sync, Path, Payload}, infinity).

%% Called by webmqx_consistent_req_broker.
rpc(async, WorkerPid, SeqId, Path, Payload) ->
    gen_server2:cast(WorkerPid, {rpc_async, self(), SeqId, Path, Payload}).

%% Called by webmqx_http_handler.
normal_publish(WorkerPid, Path, Payload) ->
	gen_server2:call(WorkerPid, {normal_publish, Path, Payload}, infinity).

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

	ExchangeDeclare = #'exchange.declare'{exchange = ?EXCHANGE_WEBMQX, type = ?EXCHANGE_WEBMQX_TYPE},
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

terminate(_Reason, #state{connection = {ConnectionRef, Connection}, rabbit_channel = {ChannelRef, Channel}}) ->
	erlang:demonitor(ConnectionRef),
	erlang:demonitor(ChannelRef),

    amqp_channel:close(Channel),
	amqp_direct_connection:server_close(Connection, <<"404">>, <<"close">>),
	amqp_connection:close(Connection),
    ok.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call({normal_publish, Path, Payload}, _From, State) ->
	{R, NewState} = internal_normal_publish(Path, Payload, State),
	{reply, R, NewState};

handle_call({rpc_sync, Path, Payload}, From, State) ->
	NewState = internal_rpc_publish(Path, Payload, _From = {rpc_sync, From}, State),
	{noreply, NewState}.

handle_cast({rpc_async, From, SeqId, Path, Payload}, State) -> 
	NewState = internal_rpc_publish(Path, Payload, _From = {rpc_async, {From, SeqId}}, State),
	{noreply, NewState};

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
             _Msg = #amqp_msg{props = #'P_basic'{correlation_id = Id},
                       payload = Payload}},
            State = #state{continuations = Conts}) ->

	{CallOrCast, From} =  dict:fetch(Id, Conts), 
	case CallOrCast of
		rpc_sync ->	
			gen_server2:reply(From, {ok, Payload});
		rpc_async ->
			{FromPid, SeqId} = From,
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

internal_rpc_publish(Path, Payload, From,
        State = #state{rabbit_channel = {_ChannelRef, Channel},
                       reply_queue = Q,
                       correlation_id = CorrelationId,
                       continuations = Continuations}) ->
    EncodedCorrelationId = base64:encode(<<CorrelationId:64>>),
    Props = #'P_basic'{correlation_id = EncodedCorrelationId,
                       content_type = <<"application/octet-stream">>,
                       reply_to = Q},

    Publish = #'basic.publish'{exchange = ?EXCHANGE_WEBMQX, 
                               routing_key = Path,
                               mandatory = true},

    amqp_channel:call(Channel, Publish, #amqp_msg{props = Props,
                                                  payload = Payload}),

    State#state{correlation_id = CorrelationId + 1,
                continuations = dict:store(EncodedCorrelationId, From, Continuations)}.

internal_normal_publish(Path, Payload,
        State = #state{rabbit_channel = {_ChannelRef, Channel}, consistent_req_queues = ConsReqQueues}) ->
	NewState = 
	case gb_sets:is_element(Path, ConsReqQueues) of
		true -> State;
		false ->
			#'queue.declare_ok'{queue = _Q} =
				amqp_channel:call(Channel, #'queue.declare'{queue       = Path,
															durable     = true,
															auto_delete = false}),	 
			State#state{consistent_req_queues = gb_sets:add(Path, ConsReqQueues)}
	end,

    Publish = #'basic.publish'{exchange = <<"">>,
                               routing_key = Path,
                               mandatory = true},

    case amqp_channel:call(Channel, Publish, #amqp_msg{payload = Payload}) of
		ok ->
			{ok, NewState};
		Error ->
			{Error, NewState}	
	end.
