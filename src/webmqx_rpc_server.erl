%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License at
%% http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%% License for the specific language governing rights and limitations
%% under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

%% @doc This is a utility module that is used to expose an arbitrary function
%% via an asynchronous RPC over AMQP mechanism. It frees the implementor of
%% a simple function from having to plumb this into AMQP. Note that the
%% RPC server does not handle any data encoding, so it is up to the callback
%% function to marshall and unmarshall message payloads accordingly.
-module(webmqx_rpc_server).

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

%%--------------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------------

%% @spec (Connection, Queue, RpcHandler) -> RpcServer
%% where
%%      Connection = pid()
%%      Queue = binary()
%%      RpcHandler = function()
%%      RpcServer = pid()
%% @doc Starts, and links to, a new RPC server instance that receives
%% requests via a specified queue and dispatches them to a specified
%% handler function. This function returns the pid of the RPC server that
%% can be used to stop the server.
start_link(ServerName, RoutingKey, Fun) ->
    {ok, Pid} = gen_server2:start_link(?MODULE, [ServerName, RoutingKey, Fun], []),
	{ok, Pid}.

%% @spec (RpcServer) -> ok
%% where
%%      RpcServer = pid()
%% @doc Stops an exisiting RPC server.
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

	ExchangeDeclare = #'exchange.declare'{exchange = ?EXCHANGE_WEBMQX, type = ?EXCHANGE_WEBMQX},
	#'exchange.declare_ok'{} = 
		amqp_channel:call(Channel, ExchangeDeclare),

	%%huotianjun 用一个临时的Q
	#'queue.declare_ok'{queue = Q} =
		amqp_channel:call(Channel, #'queue.declare'{exclusive   = true,
													durable		= false,
													auto_delete = true}),

	%%huotianjun 这个里面的routing_key没有什么功能用途，仅仅定义微服务的实例名
	Bind = #'queue.bind'{queue = Q, exchange = ?EXCHANGE_WEBMQX, routing_key = RoutingKey, arguments = [ServerName]},
	#'queue.bind_ok'{} = amqp_channel:call(Channel, Bind),

	%%huotianjun 效率第一，不用ack。（这个需要再权衡一下，如果channel启用basic.qos，需要设置prefetch_count。可以根据consumer的处理能力来发消息）
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
	%%io:format("rpc server received: ~p ~p ~n", [CorrelationId, Q]),
	%%worker_pool:submit_async(
%%		fun() ->
			Response = Fun(Payload),
			%%huotianjun 这个重要，把CorrelationId再打回到返回详细中，让接收的channel知道这个消息给谁
			Properties = #'P_basic'{correlation_id = CorrelationId},
			Publish = #'basic.publish'{exchange = <<>>,
                               routing_key = Q},
			amqp_channel:call(Channel, Publish, #amqp_msg{props = Properties,
                                                  payload = Response}),
%%		end),
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
