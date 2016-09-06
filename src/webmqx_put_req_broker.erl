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
-module(webmqx_put_req_broker).

-behaviour(gen_server2).

-include("webmqx.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([start_link/1]).
-export([stop/1]).

-record(state, {connection, channel, path,
				continuations = dict:new(),
				seq_id = 0}).

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
start_link(Path) ->
    {ok, Pid} = gen_server2:start_link(?MODULE, [Path], []),
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
init([Path]) ->
	process_flag(trap_exit, true),
	
	{ok, Connection} = amqp_connection:start(#amqp_params_direct{}),

    {ok, Channel} = amqp_connection:open_channel(
                        Connection, {amqp_direct_consumer, [self()]}),

	%%huotianjun enable rabbit_limiter 
	#'basic.qos_ok'{} = amqp_channel:call(
							Channel, #'basic.qos'{prefetch_count = 10}),

	#'queue.declare_ok'{queue = Q} =
		amqp_channel:call(Channel, #'queue.declare'{queue		= Path,
													durable		= true,
													auto_delete = false}),

    amqp_channel:call(Channel, #'basic.consume'{queue = Q, no_ack = false}),

	ConnectionRef = erlang:monitor(process, Connection),
	ChannelRef = erlang:monitor(process, Channel),
    {ok, #state{connection = {ConnectionRef, Connection}, channel = {ChannelRef, Channel}, 
				path = Path}}.

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
%% huotianjun from PutReq Queue of Path
handle_info({#'basic.deliver'{delivery_tag = DeliveryTag},
				#amqp_msg{payload = PayloadJson}},
				State = #state{path = Path, channel = {_Ref, Channel},
								seq_id = SeqId,
								continuations = Continuations}) ->
	NewState = 
	try 
		case webmqx_rpc_channel_manager:get_a_pid() of
			undefined -> 
				amqp_channel:call(Channel, #'basic.nack'{delivery_tag = DeliveryTag}),
				State;
			{ok, ChannelPid} ->
				webmqx_rpc_channel:rpc(cast, ChannelPid, SeqId, Path, PayloadJson),
				State#state{seq_id = SeqId + 1,
					continuations = dict:store(SeqId, DeliveryTag, Continuations)}
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

%%--------------------------------------------------------------------------
%% Rest of the gen_server callbacks
%%--------------------------------------------------------------------------

%%huotianjun from webmqx_rpc_channel
handle_cast({rpc_reply, SeqId, Response}, 
				State = #state{channel = {_Ref, Channel},
								continuations = Continuations}) ->
	DeliveryTag =  dict:fetch(SeqId, Continuations),
	case Response of
		no_server ->
			dict:fold(fun (_SeqId, DeliveryTag, ok) ->
							amqp_channel:call(Channel, #'basic.nack'{delivery_tag = DeliveryTag});
						end, ok, Continuations),
			{stop, normal, State};
		{ok, _} ->
			amqp_channel:call(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
			{noreply, State#state{continuations = dict:erase(SeqId, Continuations)}}
	end,

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

nack_all(#state{



