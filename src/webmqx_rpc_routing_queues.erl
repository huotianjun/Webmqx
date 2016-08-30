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

-module(webmqx_rpc_routing_queues).
-behaviour(gen_server2).

%%huotianjun 用于同步routing queues变更的消息
-behaviour(gm).

%% API.
-export([start/0]).
-export([start_link/0]).
-export([random_a_queue/1, flush_routing_queues/1]).

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
				gm = undefined,
				routing_queues= dict:new() %%huotianjun value内容是gb_trees结构, key是path split words
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

random_a_queue(Path) ->
	case get_routing_queues(Path) of
		undefined -> undefined;
		{ok, QueueTrees} ->
			Size = queue_trees_size(QueueTrees),
			N = erlang:phash2(self(), Size) + 1,
			queue_trees_lookup(N, QueueTrees)
	end.

%%huotianjun 结果是gb_trees
get_routing_queues(Path) when is_binary(Path) ->
	Words = rabbit_exchange_type_webmqx:split_topic_key(Path),
	get_routing_queues1(Words).

get_routing_queues1([]) -> undefined;
get_routing_queues1(PathSplitWords) ->
	case ets:lookup(?TAB, {path, PathSplitWords}) of
		[] ->
			gen_server2:call(?MODULE, {get_routing_queue, PathSplitWords}, infinity);

		%%huotianjun 刚才get过，没有得到
		[{none, LastStampCounter}] -> 
			NowTimeStampCounter = now_timestamp_counter(),
			if
				(NowTimeStampCounter - LastStampCounter) > 10 ->
					gen_server2:call(?MODULE, {get_routing_queue, PathSplitWords}, infinity);
				true -> undefined	
			end;
		[QueuesTree] ->
			{ok, QueuesTree}
	end.
				
%%huotianjun 在rabbit_exchange_type_webmqx中发起		
flush_routing_queues(PathSplitWords) ->
	gen_server2:cast(?MODULE, {flush_routing_queues, PathSplitWords}).

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

%%huotianjun 这个只是本节点get，并不gm广播
handle_call({get_routing_queues, PathSplitWords}, _, State = #state{routing_queues = RoutingQueues}) ->
	QueueTrees1=
	case dict:find(PathSplitWords, RoutingQueues) of
		{ok, QueueTrees0} -> 
			case gb_trees:is_empty(QueueTrees0) of
				true -> undefined;
				false -> QueueTrees0
			end;
		error ->
			undefined
	end,

	case QueueTrees1 of 
		undefined ->
			%%huotianjun 保护一下
			NowTimeStampCounter = now_timestamp_counter(),
			GoFetch = 
			case ets:lookup(?TAB, {path, PathSplitWords}) of
				%%huotianjun 上次没有读到的情况
				[{none, LastStampCounter}] -> 
					if
						(NowTimeStampCounter - LastStampCounter) > 10 -> true;
						true -> false
					end;
				_ -> true
			end,
			
			case GoFetch of		
				true ->
					case rabbit_exchange_type_webmqx:fetch_routing_queues(PathSplitWords) of
						[] ->
							true = ets:insert(?TAB, {{path, PathSplitWords}, {none, NowTimeStampCounter}}),
							{reply, undefined, State};
						Queues ->
							QueueTrees = queue_trees_new(Queues),
							true = ets:insert(?TAB, {{path, PathSplitWords}, QueueTrees}),
							{reply, {ok, QueueTrees}, 
								State#state{routing_queues = 
												dict:store(PathSplitWords, QueueTrees, RoutingQueues)}} 
					end;
				false ->
					{reply, undefined, State}
			end;
		_ -> {reply, {ok, QueueTrees1}, State} 
	end;

handle_call(_Request, _From, State) ->
	{reply, ignore, State}.

%%huotianjun 第一次用某path的时候，以及add_binding、remove_binding的时候
%%huotianjun gm:broadcast(GM, {flush_rpc_routing_queues, PathSplitWords}),

handle_cast({flush_rpc_routing_queues, PathSplitWords}, State = #state{gm = GM}) ->
	gm:broadcast(GM, {flush_rpc_routing_queues, PathSplitWords}),
	{noreply, State};

%%huotianjun 统一在这里处理flush
handle_cast({gm, {flush_rpc_routing_queues, PathSplitWords}}, State = #state{routing_queues = RoutingQueues}) ->
	QueueTrees =
	case rabbit_exchange_type_webmqx:fetch_routing_queues(PathSplitWords) of
		[] ->
			true = ets:insert(?TAB, {{path, PathSplitWords}, {none, now_timestamp_counter()}}),
			gb_trees:empty();
		Queues ->
			QueueTrees1 = queue_trees_new(Queues),
			true = ets:insert(?TAB, {{path, PathSplitWords}, QueueTrees1}),
			QueueTrees1 
	end,
	{noreply, State#state{routing_queues = dict:store(PathSplitWords, QueueTrees, RoutingQueues)}};

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

now_timestamp_counter() ->
	{{NowYear, NowMonth, NowDay},{NowHour, NowMinute, NowSecond}} = calendar:now_to_local_time(os:timestamp()),
	(NowYear*10000 + NowMonth*100 + NowDay)*3600*24 + (NowHour*3600 + NowMinute*60 + NowSecond).

queue_trees_size(QueueTrees) ->
	gb_trees:size(QueueTrees).

queue_trees_lookup(Number, QueueTrees) ->
	case gb_trees:lookup(Number, QueueTrees) of 
		{value,	Queue} -> {ok, Queue};
		none        -> undefined
	end.

queue_trees_enter(Number, Queue, QueueTrees) ->
	gb_trees:enter(Number, Queue, QueueTrees).

queue_trees_new(Queues) ->
	queue_trees_new1(Queues, gb_trees:empty(), 1).

queue_trees_new1([], QueueTrees, _Count) -> {ok, QueueTrees};
queue_trees_new1([Queue|Left], QueueTrees, Count) ->
	queue_trees_new1(Left, queue_trees_enter(Count, Queue, QueueTrees), Count+1). 


	
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
