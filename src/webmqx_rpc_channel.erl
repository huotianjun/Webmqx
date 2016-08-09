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

%% @doc This module allows the simple execution of an asynchronous RPC over
%% AMQP. It frees a client programmer of the necessary having to AMQP
%% plumbing. Note that the this module does not handle any data encoding,
%% so it is up to the caller to marshall and unmarshall message payloads
%% accordingly.
-module(webmqx_rpc_channel).

-include_lib("amqp_client/include/amqp_client.hrl").

-behaviour(gen_server2).

-export([start_link/1, stop/1]).
-export([call/3]).
-export([declare_exchange/2]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).

-record(state, {
				connection,	
				channel,
                reply_queue,
                continuations = dict:new(),
                correlation_id = 0}).

%%--------------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------------

%% @spec (Connection, Queue) -> RpcClient
%% where
%%      Connection = pid()
%%      Queue = binary()
%%      RpcClient = pid()
%% @doc Starts, and links to, a new RPC channel instance that sends requests
%% to a specified queue. This function returns the pid of the RPC channel 
%% process that can be used to invoke RPCs and stop the client.
start_link(N) ->
	%%huotianjun 一个Rpc channel，启动一个Connection，紧密捆绑
	NBin = integer_to_binary(N),
	RPCClientName = atom_to_binary(?MODULE, latin1),
	ConnName = <<RPCClientName/binary, NBin/binary>>,
	{ok, Connection} = hello_util:amqp_connect(ConnName),
    {ok, Pid} = gen_server2:start_link(?MODULE, [N, Connection], []),
	%%huotianjun 注意：如果这里不返回{ok, Pid}，在supstart_child的时候会出问题的
	{ok, Pid}.

%% @spec (RpcClient) -> ok
%% where
%%      RpcClient = pid()
%% @doc Stops an exisiting RPC client.
stop(Pid) ->
    gen_server2:call(Pid, stop, infinity).

declare_port(RpcClient, ExchangeName) when is_binary(ExchangeName) ->
	gen_server2:cast(RpcClient, {declare_port, ExchangeName}).

%% @spec (RpcClient, Payload) -> ok
%% where
%%      RpcClient = pid()
%%      Payload = binary()
%% @doc Invokes an RPC. Note the caller of this function is responsible for
%% encoding the request and decoding the response.
%%
%% huotianjun to-do 这个异常需要输出到特殊队列中
call(_RpcClient, undefined,  _Payload) -> <<"no service">>;

%%huotianjun 实现的时候，是发起cast，避免阻塞
call(RpcClient, PortKey, Payload) ->
    gen_server2:call(RpcClient, {call, PortKey, Payload}, 5000).

%%--------------------------------------------------------------------------
%% Plumbing
%%--------------------------------------------------------------------------

%% Sets up a reply queue for this client to listen on
%% huotianjun Q<<"amq.rabbitmq.reply-to">>是个虚拟Queue
setup_reply_queue(State = #state{channel = {_Ref, Channel}, reply_queue = Q}) ->
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue = Q}),
    State.

%% Registers this RPC client instance as a consumer to handle rpc responses
setup_consumer(#state{channel = {_Ref, Channel}, reply_queue = Q}) ->
	%%huotianjun Q必须是<<"amq.rabbitmq.reply-to">>，channel里面要特殊准备一下，会补充特殊信息到Props中
    #'basic.consume_ok'{} =
		amqp_channel:call(Channel, #'basic.consume'{queue = Q, no_ack = true}).

%% Publishes to the broker, stores the From address against
%% the correlation id and increments the correlationid for
%% the next request
publish({Payload, ExchangeKey}, From,
        State = #state{channel = {_ChannelRef, Channel},
                       reply_queue = Q,
                       correlation_id = CorrelationId,
                       continuations = Continuations}) ->
    EncodedCorrelationId = base64:encode(<<CorrelationId:64>>),
    Props = #'P_basic'{correlation_id = EncodedCorrelationId,
                       content_type = <<"application/octet-stream">>,
					   %%huotianjun 这个很重要，在basic.publish的时候，会修改这个，补充返回路由
					   %%huotianjun 会用maybe_set_fast_reply_to处理reply_to是<<"amq.rabbitmq.reply-to">>的情况
                       reply_to = Q},

    Publish = #'basic.publish'{exchange = ExchangeKey,
                               routing_key = <<>>,
                               mandatory = true},

    amqp_channel:call(Channel, Publish, #amqp_msg{props = Props,
                                                  payload = Payload}),

	%%huotianjun 这个Id非常重要，RPC的返回消息中还保留它，根据它可以知道，消息是返回是给哪个进程的
	%%huotianjun 因为rpc的call是cast方式发起的！
    State#state{correlation_id = CorrelationId + 1,
				%%huotianjun 记录一下，这个Id的RPC消息返回后，交给哪个From
                continuations = dict:store(EncodedCorrelationId, From, Continuations)}.

%%--------------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------------

%% Sets up a reply queue and consumer within an existing channel
%% @private
init([N, Connection]) ->
	process_flag(trap_exit, true),
	%%huotianjun 一个RPC client用一个channel
    {ok, Channel} = amqp_connection:open_channel(
                        Connection, {amqp_direct_consumer, [self()]}),

	%%error_logger:info_msg("Connection : ~p Channel : ~p ~n", [Connection, Channel]),

	ConnectionRef = erlang:monitor(process, Connection),
	ChannelRef = erlang:monitor(process, Channel),

    InitialState = #state{
							connection  = {ConnectionRef, Connection},
							channel     = {ChannelRef, Channel},
							reply_queue = <<"amq.rabbitmq.reply-to">>
						 },

    State = setup_reply_queue(InitialState),
    setup_consumer(State),

	%%huotianjun 在管理器上注册一下本Client
	hello_rpc_channel_manager:join(N, self()),
    {ok, State}.

%% Closes the channel this gen_server instance started
%% @private
%% huotianjun RoutingKey在rpc 调用中，其实就是Queue
terminate(_Reason, #state{connection = {ConnectionRef, Connection}, channel = {ChannelRef, Channel}}) ->
	erlang:demonitor(ConnectionRef),
	erlang:demonitor(ChannelRef),

    amqp_channel:close(Channel),
	amqp_direct_connection:server_close(Connection, <<"404">>, <<"close">>),
	amqp_connection:close(Connection),

	error_logger:info_msg("close connection : ~p ~n", [Connection]),
    ok.

%% Handle the application initiated stop by just stopping this gen server
%% @private
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

%% @private
handle_call({call, PortKey, Payload}, From, State) ->
    NewState = publish({Payload, PortKey}, From, State),
	%%huotianjun noreply非常重要，这样，这个channel不会被阻塞(只是call的应用进程被阻塞了），rpc channel还可以继续被call
    {noreply, NewState}.

handle_cast({declare_port, ExchangeName}, State = #state{channel = {_ChannelRef, Channel}}) ->
	ExchangeDeclare = #'exchange.declare'{exchange = ExchangeName, type = <<"x-random">>},
	#'exchange.declare_ok'{} =
		amqp_channel:call(Channel, ExchangeDeclare),
	{noreply, State};

%% @private
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
%% huotianjun 收到返回消息
handle_info({#'basic.deliver'{},
			 %%huotianjun 这个Id非常重要，根据它可以知道，这个返回是给哪个进程的
             _Msg = #amqp_msg{props = #'P_basic'{correlation_id = Id},
                       payload = Payload}},
            State = #state{continuations = Conts}) ->
	%%error_logger:info_msg("channel get reply : ~p ~n", [Msg]), 
	%%error_logger:info_msg("ok ~n", []), 
    From = dict:fetch(Id, Conts),
    gen_server:reply(From, Payload),
    {noreply, State#state{continuations = dict:erase(Id, Conts) }};

handle_info({'EXIT', _Pid, Reason}, State) ->
	{stop, Reason, State};

%%huotianjun Connection出问题了
handle_info({'DOWN', _MRef, process, _Pid, Reason}, State) ->
	{stop, {error, Reason}, State}.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
