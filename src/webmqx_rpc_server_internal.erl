%% This is the version of rabbit_rpc_server from RabbitMQ.
%%

%% @doc This is a utility module that is used to expose an arbitrary function
%% via an asynchronous RPC over AMQP mechanism. It frees the implementor of
%% a simple function from having to plumb this into AMQP. Note that the
%% RPC server does not handle any data encoding, so it is up to the callback
%% function to marshall and unmarshall message payloads accordingly.
-module(webmqx_rpc_server_internal).

-behaviour(gen_server2).

-include("webmqx.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([start_link/3]).
-export([stop/1]).

-record(state, {connection, channel,
				queue,
				server_name,
                handler}).

-ifdef(use_specs).

-spec(start_link/3 :: (binary(), binary(), function()) -> rabbit_types:ok(pid())). 

-endif.
%%--------------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------------

start_link(ServerName, RoutingKey, Fun) ->
    {ok, Pid} = gen_server2:start_link(?MODULE, [ServerName, RoutingKey, Fun], []),
	{ok, Pid}.

stop(Pid) ->
    gen_server2:call(Pid, stop, infinity).

%%--------------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------------

%% @private
init([ServerName, RoutingKey, Fun]) ->
	process_flag(trap_exit, true),
	
	{ok, Connection} = amqp_connection:start(#amqp_params_direct{}),

    {ok, Channel} = amqp_connection:open_channel(
                        Connection, {amqp_direct_consumer, [self()]}),

	ExchangeDeclare = #'exchange.declare'{exchange = ?EXCHANGE_WEBMQX, type = ?EXCHANGE_WEBMQX_TYPE},
	#'exchange.declare_ok'{} = 
		amqp_channel:call(Channel, ExchangeDeclare),

	#'queue.declare_ok'{queue = Q} =
		amqp_channel:call(Channel, #'queue.declare'{exclusive   = true,
													durable		= false,
													auto_delete = true}),

	Bind = #'queue.bind'{queue = Q, exchange = ?EXCHANGE_WEBMQX, routing_key = RoutingKey, arguments = [{server_name, ServerName}]},
	#'queue.bind_ok'{} = amqp_channel:call(Channel, Bind),

    amqp_channel:call(Channel, #'basic.consume'{queue = Q, no_ack = true}),

	ConnectionRef = erlang:monitor(process, Connection),
	ChannelRef = erlang:monitor(process, Channel),
    {ok, #state{connection = {ConnectionRef, Connection}, channel = {ChannelRef, Channel}, 
				queue = Q,
				server_name = ServerName,
				handler = Fun}}. 

%% @private
handle_info(shutdown, State) ->
    {stop, normal, State};

%% @private
handle_info({#'basic.consume'{}, _}, State) ->
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
handle_info({#'basic.deliver'{delivery_tag = _DeliveryTag},
             #amqp_msg{props = Props, payload = Payload}},
            State = #state{handler = Fun, channel = {_Ref, Channel}}) ->
	#'P_basic'{correlation_id = CorrelationId,
               reply_to = Q} = Props,
	Response = Fun(Payload),
	Properties = #'P_basic'{correlation_id = CorrelationId},
	Publish = #'basic.publish'{exchange = <<>>,
                               routing_key = Q},
	amqp_channel:call(Channel, Publish, #amqp_msg{props = Properties,
                                                  payload = Response}),
    {noreply, State};

handle_info({'EXIT', _Pid, Reason}, State) ->
	{stop, Reason, State};

%% @private
handle_info({'DOWN', _MRef, process, _Pid, Reason}, State) ->
	{stop, {error, Reason}, State}.

%% @private
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

%%--------------------------------------------------------------------------
%% Rest of the gen_server callbacks
%%--------------------------------------------------------------------------

%% @private
handle_cast(_Message, State) ->
    {noreply, State}.

%% Closes the channel this gen_server instance started
%% @private
terminate(_Reason, #state{connection = {_ConnectionRef, Connection}, channel = {_ChannelRef, Channel}}) ->
    amqp_channel:close(Channel),
	amqp_direct_connection:server_close(Connection, <<"404">>, <<"close">>),
	amqp_connection:close(Connection),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
