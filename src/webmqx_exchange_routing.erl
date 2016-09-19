-module(webmqx_exchange_routing).

-include_lib("rabbit/include/gm_specs.hrl").
-include("webmqx.hrl").

-behaviour(gen_server2).

%%huotianjun for update exchange bindings of all clusters.
-behaviour(gm).

%% API.
-export([start/0]).
-export([start_link/0]).
-export([route/1, flush_routing_queues/1, queues_count/1]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%huotianjun gm callback 
-export([joined/2, members_changed/3, handle_msg/3, handle_terminate/2]).

-define(TAB, ?MODULE).

-record(state, {
				gm = undefined,
				routing_queues= dict:new() %%huotianjun value is gb_trees, key is splited path.
				}). 

-ifdef(use_specs).

-spec(start_link/0 :: () -> rabbit_types:ok_pid_or_error().
-spec(start/0 :: () -> rabbit_types:ok_or_error(any())).

-spec(route/1 :: (binary()) -> [rabbit_types:binding_destination()]).
-spec(flush_routing_queues/1 :: (binary()) -> 'ok').
-spec(queues_count/1 :: (binary()) -> non_neg_integer()).

-endif.

%% API.

start_link() ->
	gen_server2:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
	?TAB = ets:new(?TAB, [
		ordered_set, public, named_table]),
    ensure_started().

%%huotianjun callback of rabbit_exchange_type_webmqx:route
route(Path) ->
	case get_queue_trees(Path) of
		undefined -> [];
		{ok, QueueTrees} ->
			%%houtianjun random a queue. 
			Size = queue_trees_size(QueueTrees),
			N = erlang:phash2(self(), Size) + 1,
			{ok, Queue} = queue_trees_lookup(N, QueueTrees),
			[Queue]
	end.

get_queue_trees(Path) when is_binary(Path) ->
	Words = webmqx_util:path_to_words(Path),
	get_queue_trees1(Words).

get_queue_trees1([]) -> undefined;
get_queue_trees1(PathSplitWords) ->
	case ets:lookup(?TAB, {path, PathSplitWords}) of
		[] ->
			gen_server2:call(?MODULE, {get_routing_queues, PathSplitWords}, infinity);

		[{{path, PathSplitWords}, {none, LastTryStamp}}] -> 
			NowTimeStamp = now_timestamp_counter(),
			if
				(NowTimeStamp - LastTryStamp) > 10 ->
					gen_server2:call(?MODULE, {get_routing_queues, PathSplitWords}, infinity);
				true -> undefined	
			end;
		[{{path, _PathSplitWords}, QueueTrees}] ->
			{ok, QueueTrees}
	end.

queues_count(Path) ->
	case get_queue_trees(Path) of
		undefined -> 0;
		{ok, QueueTrees} ->
			_Size = queue_trees_size(QueueTrees)
	end.

%%huotianjun from rabbit exchange binding event	
flush_routing_queues(PathSplitWords) ->
	gen_server2:cast(?MODULE, {flush_routing_queues, PathSplitWords}).

%% gen_server.

init([]) ->
	%%huotianjun group name is MODULE
	{ok, GM} = gm:start_link(?MODULE, ?MODULE, [self()],
							 fun rabbit_misc:execute_mnesia_transaction/1),
	MRef = erlang:monitor(process, GM),

	receive
		{joined, GM}            -> error_logger:info_msg("webmqx_exchange_routing_gm ~p is joined~n", [GM]),
									erlang:demonitor(MRef, [flush]),
									ok;
		{'DOWN', MRef, _, _, _} -> error_logger:info_msg("start link gm DOWN!"),		
									ok 
	end,
	error_logger:info_msg("webmqx_exchange_routing is started"),

	{ok, #state{gm = GM}}.

%%huotianjun no gm broadcast.
handle_call({get_routing_queues, PathSplitWords}, _, State = #state{routing_queues = RoutingQueues}) ->
	QueueTrees1=
	case dict:find({path, PathSplitWords}, RoutingQueues) of
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
			%%huotianjun
			NowTimeStamp = now_timestamp_counter(),
			GoFetch = 
			case ets:lookup(?TAB, {path, PathSplitWords}) of
				%%huotianjun last fetch just before is null
				[{{path, PathSplitWords}, {none, LastTryStamp}}] -> 
					if
						%%huotianjun 10 seconds
						(NowTimeStamp - LastTryStamp) > 10 -> true;
						true -> false
					end;
				_ -> true
			end,
			
			case GoFetch of		
				true ->
					case rabbit_exchange_type_webmqx:fetch_routing_queues(<<"/">>, ?EXCHANGE_WEBMQX, PathSplitWords) of
						[] ->
							routing_table_update(PathSplitWords, {none, NowTimeStamp}),
							{reply, undefined, 
								State#state{routing_queues =
												dict:store({path, PathSplitWords}, gb_trees:empty(), RoutingQueues)}};
						Queues ->
							{ok, QueueTrees} = queue_trees_new(Queues),
							routing_table_update(PathSplitWords, QueueTrees),
							{reply, {ok, QueueTrees}, 
								State#state{routing_queues = 
												dict:store({path, PathSplitWords}, QueueTrees, RoutingQueues)}} 
					end;
				false ->
					{reply, undefined, State}
			end;
		_ -> {reply, {ok, QueueTrees1}, State} 
	end;

handle_call(_Request, _From, State) ->
	{reply, ignore, State}.

handle_cast({flush_routing_queues, PathSplitWords}, State = #state{gm = GM}) ->
	gm:broadcast(GM, {flush_routing_queues, PathSplitWords}),
	{noreply, State};

%%huotianjun all clusters update in here
handle_cast({gm, {flush_routing_queues, PathSplitWords}}, State = #state{routing_queues = RoutingQueues}) ->
	QueueTrees =
	case rabbit_exchange_type_webmqx:fetch_routing_queues(<<"/">>, ?EXCHANGE_WEBMQX, PathSplitWords) of
		[] ->
			routing_table_update(PathSplitWords, {none, now_timestamp_counter()}),
			gb_trees:empty();
		Queues ->
			{ok, QueueTrees1} = queue_trees_new(Queues),
			routing_table_update(PathSplitWords, QueueTrees1),
			QueueTrees1 
	end,
	{noreply, State#state{routing_queues = dict:store({path, PathSplitWords}, QueueTrees, RoutingQueues)}};

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
            ok
    end.

%% Local Functions
now_timestamp_counter() ->
	{{_, _, _},{NowHour, NowMinute, NowSecond}} = calendar:now_to_local_time(os:timestamp()),
	(NowHour*3600 + NowMinute*60 + NowSecond).

queue_trees_size(QueueTrees) ->
	gb_trees:size(QueueTrees).

queue_trees_lookup(Number, QueueTrees) ->
	case gb_trees:lookup(Number, QueueTrees) of 
		{value,	Queue} -> {ok, Queue};
		none        -> undefined
	end.

queue_trees_enter(Number, Queue, QueueTrees) ->
	gb_trees:enter(Number, Queue, QueueTrees).

%%huotianjun new from queues list
queue_trees_new(Queues) ->
	queue_trees_new1(Queues, gb_trees:empty(), 1).

queue_trees_new1([], QueueTrees, _Count) -> {ok, QueueTrees};
queue_trees_new1([Queue|Rest], QueueTrees, Count) ->
	queue_trees_new1(Rest, queue_trees_enter(Count, Queue, QueueTrees), Count+1). 
	
routing_table_update(PathSplitWords, QueueTrees) ->
	case ets:insert_new(?TAB, {{path, PathSplitWords}, QueueTrees}) of
		true ->
			ok;
		false ->
			ets:update_element(?TAB, {{path, PathSplitWords}, {2, QueueTrees}})
	end.

%%huotianjun gm's callback
joined([SPid], _Members) -> 
	SPid ! {joined, self()}, ok.

members_changed([_SPid], _Births, _) ->
    ok.

handle_msg([SPid], _From, Msg) ->
    ok = gen_server2:cast(SPid, {gm, Msg}).

handle_terminate([_SPid], Reason) ->
	error_logger:info_msg("handle_terminate Reason : ~p ~n", [Reason]),
    ok.
