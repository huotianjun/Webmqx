-module(webmqx_exchange_routes).

-include_lib("rabbit/include/gm_specs.hrl").
-include("webmqx.hrl").

-behaviour(gen_server2).

%% For update exchange bindings of all nodes.
-behaviour(gm).

%% APIs.
-export([start/0]).
-export([start_link/0]).
-export([route/1, flush_queues/1, queues_count/1]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% GM callbacks 
-export([joined/2, members_changed/3, handle_msg/3, handle_terminate/2]).

-define(TAB, ?MODULE).

-record(state, {
				vhost = webmqx_util:env_vhost(),
				gm = undefined,
				routing_queues= dict:new() %% The key is words of path, and value is a gb_trees.
				}). 

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(start_link/0 :: () -> rabbit_types:ok_pid_or_error().
-spec(start/0 :: () -> rabbit_types:ok_or_error(any())).

-spec(route/1 :: (binary()) -> [rabbit_types:binding_destination()]).
-spec(flush_queues/1 :: (binary()) -> 'ok').
-spec(queues_count/1 :: (binary()) -> non_neg_integer()).

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported functions
%%%

start_link() ->
	gen_server2:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
	?TAB = ets:new(?TAB, [
		ordered_set, public, named_table]),
    ensure_started().

%% Callback from rabbit_exchange_type_webmqx:route
route(Path) ->
	case get_queue_trees(Path) of
		undefined -> [];
		{ok, QueueTrees} ->
			%% Select a random queue. 
			Size = queue_trees_size(QueueTrees),
			N = erlang:phash2(self(), Size) + 1,
			{ok, Queue} = queue_trees_lookup(N, QueueTrees),
			[Queue]
	end.

get_queue_trees(Path) when is_binary(Path) ->
	Words = webmqx_util:path_to_words(Path),
	get_queue_trees1(Words).

get_queue_trees1([]) -> undefined;
get_queue_trees1(WordsOfPath) ->
	case ets:lookup(?TAB, {path, WordsOfPath}) of
		[] ->
			gen_server2:call(?MODULE, {get_routing_queues, WordsOfPath}, infinity);

		[{{path, WordsOfPath}, {none, LastTryStamp}}] -> 
			NowTimeStamp = now_timestamp_counter(),
			if
				(NowTimeStamp < LastTryStamp) orelse (NowTimeStamp - LastTryStamp) > 10 ->
					gen_server2:call(?MODULE, {get_routing_queues, WordsOfPath}, infinity);
				true -> undefined	
			end;
		[{{path, _WordsOfPath}, QueueTrees}] ->
			{ok, QueueTrees}
	end.

queues_count(Path) ->
	case get_queue_trees(Path) of
		undefined -> 0;
		{ok, QueueTrees} ->
			_Size = queue_trees_size(QueueTrees)
	end.

%% Called from webmqx_binding_event_handler.
flush_queues(WordsOfPath) ->
	gen_server2:cast(?MODULE, {flush_queues, WordsOfPath}).

%%%
%%% Callbacks of gen_server
%%%

init([]) ->
	{ok, GM} = gm:start_link(?MODULE, ?MODULE, [self()],
							 fun rabbit_misc:execute_mnesia_transaction/1),
	MRef = erlang:monitor(process, GM),

	receive
		{joined, GM}            -> error_logger:info_msg("webmqx_exchange_routes_gm ~p is joined~n", [GM]),
									erlang:demonitor(MRef, [flush]),
									ok;
		{'DOWN', MRef, _, _, _} -> error_logger:info_msg("start link gm DOWN!"),		
									ok 
	end,
	error_logger:info_msg("webmqx_exchange_routes is started"),

	{ok, #state{gm = GM}}.

handle_call({get_routing_queues, WordsOfPath}, _, 
				State = #state{vhost = VHost, routing_queues = RoutingQueues}) ->
	%% First, searching in process state.
	QueueTrees1=
	case dict:find({path, WordsOfPath}, RoutingQueues) of
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
			%% Then, searching in rabbit table.
			NowTimeStamp = now_timestamp_counter(),
			GoFetch = 
			case ets:lookup(?TAB, {path, WordsOfPath}) of
				[{{path, WordsOfPath}, {none, LastTryStamp}}] -> 
					if
						%% Interval : 10 seconds
						(NowTimeStamp < LastTryStamp) orelse (NowTimeStamp - LastTryStamp) > 10 -> true;
						true -> false
					end;
				_ -> true
			end,
			
			case GoFetch of		
				true ->
					case rabbit_exchange_type_webmqx:fetch_routing_queues(VHost, ?EXCHANGE_WEBMQX, WordsOfPath) of
						[] ->
							routing_table_update(WordsOfPath, {none, NowTimeStamp}),
							{reply, undefined, 
								State#state{routing_queues =
												dict:store({path, WordsOfPath}, gb_trees:empty(), RoutingQueues)}};
						Queues ->
							{ok, QueueTrees} = queue_trees_new(Queues),
							routing_table_update(WordsOfPath, QueueTrees),
							{reply, {ok, QueueTrees}, 
								State#state{routing_queues = 
												dict:store({path, WordsOfPath}, QueueTrees, RoutingQueues)}} 
					end;
				false ->
					{reply, undefined, State}
			end;
		_ -> {reply, {ok, QueueTrees1}, State} 
	end;

handle_call(_Request, _From, State) ->
	{reply, ignore, State}.

handle_cast({flush_queues, WordsOfPath}, State = #state{gm = GM}) ->
	gm:broadcast(GM, {flush_queues, WordsOfPath}),
	{noreply, State};

%% All nodes update their ets tables.
handle_cast({gm, {flush_queues, WordsOfPath}}, State = #state{vhost = VHost, routing_queues = RoutingQueues}) ->
	QueueTrees =
	case rabbit_exchange_type_webmqx:fetch_routing_queues(VHost, ?EXCHANGE_WEBMQX, WordsOfPath) of
		[] ->
			routing_table_update(WordsOfPath, {none, now_timestamp_counter()}),
			gb_trees:empty();
		Queues ->
			{ok, QueueTrees1} = queue_trees_new(Queues),
			routing_table_update(WordsOfPath, QueueTrees1),
			QueueTrees1 
	end,
	{noreply, State#state{routing_queues = dict:store({path, WordsOfPath}, QueueTrees, RoutingQueues)}};

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
        _Pid ->
            ok
    end.

%%%
%%% Local Functions
%%%

now_timestamp_counter() ->
	{{_NowYear, _NowMonth, _NowDay},{NowHour, NowMinute, NowSecond}} = calendar:now_to_local_time(os:timestamp()),
	(NowHour*3600 + NowMinute*60 + NowSecond).

%% Queues of a routing key managed as gb_trees in process. 
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
queue_trees_new1([Queue|Rest], QueueTrees, Count) ->
	queue_trees_new1(Rest, queue_trees_enter(Count, Queue, QueueTrees), Count+1). 
	
routing_table_update(WordsOfPath, QueueTrees) ->
	case ets:insert_new(?TAB, {{path, WordsOfPath}, QueueTrees}) of
		true ->
			ok;
		false ->
			ets:update_element(?TAB, {path, WordsOfPath}, {2, QueueTrees})
	end.

%%%
%%% Callbacks of GM
%%%

joined([SPid], _Members) -> 
	SPid ! {joined, self()}, ok.

members_changed([_SPid], _Births, _) ->
    ok.

handle_msg([SPid], _From, Msg) ->
    ok = gen_server2:cast(SPid, {gm, Msg}).

handle_terminate([_SPid], Reason) ->
	error_logger:info_msg("handle_terminate Reason : ~p ~n", [Reason]),
    ok.
