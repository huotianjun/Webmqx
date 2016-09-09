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

%%--------------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------------

start_link(Path) ->
    {ok, Pid} = gen_server2:start_link(?MODULE, [Path], []),
	{ok, Pid}.

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

	%%huotianjun rabbit_limiter enable.
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
%% huotianjun from Consistent Req Queue named Path
handle_info({#'basic.deliver'{delivery_tag = DeliveryTag},
				#amqp_msg{payload = PayloadJson}},
				State = #state{path = Path, channel = {_Ref, Channel},
								req_id = ReqId,
								unacked_rpc_reqs = UnackedReqs}) ->
	NewState = 
	try 
		case webmqx_rpc_channel_manager:get_a_channel() of
			undefined -> 
				amqp_channel:call(Channel, #'basic.nack'{delivery_tag = DeliveryTag}),
				State;
			{ok, RpcChannelPid} ->
				webmqx_rpc_channel:rpc(async, RpcChannelPid, ReqId, Path, PayloadJson),
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

%%--------------------------------------------------------------------------
%% Rest of the gen_server callbacks
%%--------------------------------------------------------------------------

%%huotianjun not send，must handle
%%			dict:fold(fun (_ReqId, Tag, ok) ->
%%							amqp_channel:call(Channel, #'basic.nack'{delivery_tag = Tag})
%%						end, ok, UnackedReqs),
%%			{stop, normal, State};

%%huotianjun return from webmqx_rpc_channel 
handle_cast({rpc_ok, ReqId, {ok, _Response}}, 
				State = #state{channel = {_Ref, Channel},
								unacked_rpc_reqs = UnackedReqs}) ->
	DeliveryTag =  dict:fetch(ReqId, UnackedReqs),
	amqp_channel:call(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
	{noreply, State#state{unacked_rpc_reqs = dict:erase(ReqId, UnackedReqs)}};

%% @private
handle_cast(_Message, State) ->
    {noreply, State}.

%% Closes the channel this gen_server instance started
%% @private
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



