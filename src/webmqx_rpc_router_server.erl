%% Copyright (c) 2012-2015, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(webmqx_rpc_router_server).
-behaviour(gen_server2).
-behaviour(gm).

%% API.
-export([start/0]).
-export([start_link/0]).
-export([set_router/2]).
-export([get_router/1]).

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

%%huotianjun gm 必须定义
-export([joined/2, members_changed/3, handle_msg/3, handle_terminate/2]).

-define(TAB, ?MODULE).

-record(state, {
				gm = undefined
				}). 

%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
	gen_server2:start_link({local, ?MODULE}, ?MODULE, [], []).

%%huotianjun 用这个启动, 目的是让?TAB的new在start_link之外执行，避免节点重启时候new
start() ->
	%%huotianjun 创建全局table
	?TAB = ets:new(?TAB, [
		ordered_set, public, named_table]),
    ensure_started().

%%huotianjun set用gen_server，能避免冲入
set_router(RoutingKey, Queues) ->
	gen_server:call(?MODULE, {set_router, RoutingKey, Queues}).

get_router(RoutingKey) ->
	ets:lookup_element(?TAB, {router, RoutingKey}, 2).

%% gen_server.

init([]) ->
	%%huotianjun 第一个MODULE是group name
	{ok, GM} = gm:start_link(?MODULE, ?MODULE, [self()],
							 fun rabbit_misc:execute_mnesia_transaction/1),
	MRef = erlang:monitor(process, GM),

	receive
		{joined, GM}            -> rabbit_log:info("webmqx_rpc_router_server_gm ~p is joined~n", [GM]),
									erlang:demonitor(MRef, [flush]),
								   ok;
		{'DOWN', MRef, _, _, _} -> rabbit_log:info("start link gm DOWN!"),		
									ok 
	end,

	{ok, #state{gm = GM}}.

handle_call({set_router, RoutingKey, Queues}, _, State) ->
	true = ets:insert(?TAB, {{router, RoutingKey}, Queues}),
	gm:broadcast(GM, {set_rpc_router, RoutingKey, Queues, self()}),
	{reply, ok, State};

handle_call(_Request, _From, State) ->
	{reply, ignore, State}.

%%huotianjun 自己发的不管
handle_cast({gm, {set_rpc_router, RoutingKey, Queues, self()}, State) ->
	{noreply, State};
handle_cast({gm, {set_rpc_router, RoutingKey, Queues, _From}, State) ->
	true = ets:insert(?TAB, {{router, RoutingKey}, Queues}),
	{noreply, State};

handle_cast(_Request, State) ->
	{noreply, State}.

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

ensure_started() ->
    case whereis(?MODULE) of
        undefined ->
			webmqx_sup:start_restartable_child(?MODULE);
        Pid ->
            {ok, Pid}
    end.

%%huotianjun 以下几个是gm的标准回调
%%huotianjun 注意：joined是gm回调的
%%huotianjun 这4个函数是在使用gm的模块里必须定义的！！！！
joined([SPid], _Members) -> SPid ! {joined, self()}, ok.

members_changed([_SPid], _Births, _) ->
    ok.

handle_msg([SPid], _From, Msg) ->
    ok = gen_server2:cast(SPid, {gm, Msg}).

handle_terminate([_SPid], Reason) ->
	ladar_log:info("handle_terminate Reason : ~p ~n", [Reason]),
    ok.
