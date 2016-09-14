-module(webmqx_rpc_worker).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("webmqx.hrl").

-behaviour(gen_server2).

-export([start_link/1, stop/1]).
-export([rpc/4, rpc/5, publish/3]).
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

%%--------------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------------

start_link(N) ->
    {ok, Pid} = gen_server2:start_link(?MODULE, [N], []),
	{ok, Pid}.

rpc(sync, WorkerPid, Path, Payload) ->
    gen_server2:call(WorkerPid, {rpc_sync, Path, Payload}, infinity).

rpc(async, WorkerPid, SeqId, Path, Payload) ->
    gen_server2:cast(WorkerPid, {rpc_async, self(), SeqId, Path, Payload}).

%%huotianjun return ok if ok
publish(WorkerPid, Path, Payload) ->
	gen_server2:call(WorkerPid, {publish, Path, Payload}, infinity).

%% @spec (RpcClient) -> ok
%% where
%%      RpcClient = pid()
%% @doc Stops an exisiting RPC client.
stop(Pid) ->
    gen_server2:call(Pid, stop, infinity).


%%--------------------------------------------------------------------------
%% Plumbing
%%--------------------------------------------------------------------------

%% Sets up a reply queue for this client to listen on
%% huotianjun Q<<"amq.rabbitmq.reply-to">>是个虚拟Queue
setup_reply_queue(State = #state{rabbit_channel = {_Ref, Channel}, reply_queue = Q}) ->
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue = Q}),
    State.

%% Registers this RPC client instance as a consumer to handle rpc responses
setup_consumer(#state{rabbit_channel = {_Ref, Channel}, reply_queue = Q}) ->
	%%huotianjun Q必须是<<"amq.rabbitmq.reply-to">>，channel里面要特殊准备一下，会补充特殊信息到Props中。这个channel发送的所有RPC的reply_to都会回到这个channel
    #'basic.consume_ok'{} =
		amqp_channel:call(Channel, #'basic.consume'{queue = Q, no_ack = true}).

%% Publishes to the broker, stores the From address against
%% the correlation id and increments the correlationid for
%% the next request
rpc_publish(Path, Payload, From,
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

	%%huotianjun 这个Id非常重要，RPC的返回消息中还保留它，根据它可以知道，消息是返回是给哪个进程的
	%%huotianjun 因为rpc的call是cast方式发起的！
    State#state{correlation_id = CorrelationId + 1,
				%%huotianjun 记录一下，这个Id的RPC消息返回后，交给哪个From
                continuations = dict:store(EncodedCorrelationId, From, Continuations)}.

normal_publish(Path, Payload,
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

%%--------------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------------

%% Sets up a reply queue and consumer within an existing channel
%% @private
init([N]) ->
	process_flag(trap_exit, true),

	{ok, Connection} = amqp_connection:start(#amqp_params_direct{}),

    {ok, Channel} = amqp_connection:open_channel(
                        Connection, {amqp_direct_consumer, [self()]}),

	ConnectionRef = erlang:monitor(process, Connection),
	ChannelRef = erlang:monitor(process, Channel),

    InitialState = #state{
							connection  = {ConnectionRef, Connection},
							rabbit_channel     = {ChannelRef, Channel},
							reply_queue = <<"amq.rabbitmq.reply-to">>
						 },

    State = setup_reply_queue(InitialState),
    setup_consumer(State),

	webmqx_rpc_worker_manager:join(N, self()),
    {ok, State#state{n = N}}.

%% Closes the channel this gen_server instance started
%% @private
%% huotianjun RoutingKey在rpc 调用中，其实就是Queue
terminate(_Reason, #state{n = N, connection = {ConnectionRef, Connection}, rabbit_channel = {ChannelRef, Channel}}) ->
	erlang:demonitor(ConnectionRef),
	erlang:demonitor(ChannelRef),

    amqp_channel:close(Channel),
	amqp_direct_connection:server_close(Connection, <<"404">>, <<"close">>),
	amqp_connection:close(Connection),
    ok.

%% Handle the application initiated stop by just stopping this gen server
%% @private
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call({publish, Path, Payload}, _From, State) ->
	{R, NewState} = normal_publish(Path, Payload, State),
	{reply, R, NewState};

%% @private
handle_call({rpc_sync, Path, Payload}, From, State) ->
	NewState = rpc_publish(Path, Payload, _From = {rpc_sync, From}, State),
	{noreply, NewState}.

%% @private
handle_cast({rpc_async, From, SeqId, Path, Payload}, State) -> 
	NewState = rpc_publish(Path, Payload, _From = {rpc_async, {From, SeqId}}, State),
	{noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({#'basic.consume'{}, _Pid}, State) ->
    {noreply, State};

%% @private
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

%% @private
handle_info(#'basic.cancel'{}, State) ->
    {noreply, State};

%% @private
handle_info(#'basic.cancel_ok'{}, State) ->
    {stop, normal, State};

%% @private
%% huotianjun rpc return info
handle_info({#'basic.deliver'{},
			 %%huotianjun 这个Id非常重要，根据它可以知道，这个返回是给哪个进程的
             _Msg = #amqp_msg{props = #'P_basic'{correlation_id = Id},
                       payload = Payload}},
            State = #state{continuations = Conts}) ->

	%%error_logger:info_msg("channel get reply : ~p ~n", [Msg]), 
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

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
