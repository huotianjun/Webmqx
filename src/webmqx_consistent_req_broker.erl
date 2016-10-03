-module(webmqx_consistent_req_broker).

-behaviour(gen_server2).

-include("webmqx.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([start_link/1]).
-export([stop/1]).

-record(state, {connection, channel, path,
				unacked_rpc_reqs = dict:new(),
				req_id = 0}).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-specs(start_link/1 :: (binary()) -> {'ok', pid()}).
-specs(stop/1 :: (pid()) -> 'ok').

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported functions
%%%

start_link(Path) ->
    {ok, Pid} = gen_server2:start_link(?MODULE, [Path], []),
	{ok, Pid}.

stop(Pid) ->
    gen_server2:call(Pid, stop, infinity).

%%%
%%% Callbacks of gen_server
%%%

%% @private
init([Path]) ->
	process_flag(trap_exit, true),
	
	{ok, Connection} = amqp_connection:start(#amqp_params_direct{}),
    {ok, Channel} = amqp_connection:open_channel(Connection, {amqp_direct_consumer, [self()]}),

	#'basic.qos_ok'{} = 
		amqp_channel:call(Channel, #'basic.qos'{prefetch_count = 10}),
	#'queue.declare_ok'{queue = Q} =
		amqp_channel:call(Channel, #'queue.declare'{queue		= Path,
													durable		= true,
													auto_delete = false}),
	Consume = #'basic.consume_ok'{} =
		amqp_channel:call(Channel, #'basic.consume'{queue = Q, no_ack = false}),

	error_logger:info_msg("Consumer ~p ~p ~p ~n", [Path, Q, Consume]),

	ConnectionRef = erlang:monitor(process, Connection),
	ChannelRef = erlang:monitor(process, Channel),

    {ok, #state{connection = {ConnectionRef, Connection}, 
				channel = {ChannelRef, Channel}, 
				path = Path}}.

handle_info(shutdown, State) ->
    {stop, normal, State};

handle_info({#'basic.consume'{}, _}, State) ->
    {noreply, State};

handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

handle_info(#'basic.cancel'{}, State) ->
    {noreply, State};

handle_info(#'basic.cancel_ok'{}, State) ->
	error_logger:info_msg("basic.cancel_ok~n"),
    {stop, normal, State};

%% Message from the queue of consistent requests named as 'Path', and rpc it to an application server.
handle_info({Delivery = #'basic.deliver'{delivery_tag = DeliveryTag},
				#amqp_msg{payload = PayloadJson}},
				State = #state{path = Path, channel = {_Ref, Channel},
								req_id = ReqId,
								unacked_rpc_reqs = UnackedReqs}) ->
	error_logger:info_msg("~p~n", [Delivery]),
	NewState = 
	try 
		case webmqx_rpc_worker_manager:get_a_worker() of
			undefined -> 
				amqp_channel:call(Channel, #'basic.nack'{delivery_tag = DeliveryTag}),
				State;
			{ok, RpcWorkerPid} ->
				error_logger:info_msg("broker send rpc~n"),
				webmqx_rpc_worker:rpc(async, RpcWorkerPid, ReqId, Path, PayloadJson),
				State#state{req_id = ReqId + 1,
							unacked_rpc_reqs = dict:store(ReqId, DeliveryTag, UnackedReqs)}
		end
	catch 
		_Error:_Reason -> 
			amqp_channel:call(Channel, #'basic.nack'{delivery_tag = DeliveryTag}),
			State 
	end,
	{noreply, NewState};

handle_info({'EXIT', _Pid, Reason}, State) ->
	{stop, Reason, State};

%% @private
handle_info({'DOWN', _MRef, process, _Pid, Reason}, State) ->
	{stop, {error, Reason}, State}.

%% @private
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

%% Message from rpc worker, the rpc cast is ok.
handle_cast({rpc_ok, ReqId, {ok, _Response}}, 
				State = #state{channel = {_Ref, Channel},
								unacked_rpc_reqs = UnackedReqs}) ->
	DeliveryTag =  dict:fetch(ReqId, UnackedReqs),
	amqp_channel:call(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
	{noreply, State#state{unacked_rpc_reqs = dict:erase(ReqId, UnackedReqs)}};

handle_cast(_Message, State) ->
    {noreply, State}.

terminate(_Reason, #state{connection = {_ConnectionRef, Connection}, 
							channel = {_ChannelRef, Channel},
							unacked_rpc_reqs = UnackedReqs}) ->
	dict:fold(fun (_ReqId, Tag, ok) ->
				amqp_channel:call(Channel, #'basic.nack'{delivery_tag = Tag})
			end, ok, UnackedReqs),

    amqp_channel:close(Channel),
	amqp_direct_connection:server_close(Connection, <<"404">>, <<"close">>),
	amqp_connection:close(Connection),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
