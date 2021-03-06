-module(webmqx_rpc_worker_manager).
-behaviour(gen_server2).

-include("webmqx.hrl").

-export([join/2, get_a_worker/1]).
-export([start/0, start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

%%----------------------------------------------------------------------------

-define(TAB, rpc_worker_table).

-ifdef(use_specs).

-spec(start_link/0 :: () -> rabbit_types:ok_pid_or_error().
-spec(start/0 :: () -> rabbit_types:ok_or_error(any())).
-spec(join/2 :: (non_neg_integer(), pid()) -> 'ok').
-spec(get_a_worker/1 :: (non_neg_integer()) -> rabbit_types:ok(pid()) | undefined). 

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

join(N, Pid) when is_pid(Pid) ->
    gen_server2:cast(?MODULE, {join, N, Pid}).

get_a_worker(WorkersNum) ->
    %% Random.
    N = erlang:phash2(self(), WorkersNum) + 1,
    get_a_worker1(N, {undefined, undefined}, WorkersNum).

get_a_worker1(_N, {L, _}, _WorkersNum) when L =/= undefined andalso L =< 0 ->
    undefined;
get_a_worker1(N, {L, Count}, WorkersNum) ->
    case ets:lookup(?TAB, {n, N}) of
        [{{n, N}, {Pid, _Ref}}] ->
            {ok, Pid};
        _ ->
            %% A bad one, so the other.
            case L of
                undefined ->
                    Count0 = WorkersNum,
                    get_a_worker1(case N+1 > Count0 of true -> 1; false -> N+1 end, {Count0 - 1, Count0}, WorkersNum);
                _ ->
                    get_a_worker1(case N+1 > Count of true -> 1; false -> N+1 end, {L - 1, Count}, WorkersNum)
            end
    end.

%%%
%%% Callbacks of gen_server
%%%

-record(state, {}).

init([]) ->
    [join_rpc(N, Pid) ||
        [N, {Pid, _Ref}] <- ets:match(?TAB, {{n, '$1'}, '$2'})],
    {ok, #state{}}.

handle_call(sync, _From, S) ->
    {reply, ok, S};

handle_call(Request, From, S) ->
    error_logger:warning_msg("The rpc worker manager server received an unexpected message:\n"
                             "handle_call(~p, ~p, _)\n",
                             [Request, From]),
    {noreply, S}.

handle_cast({join, N, Pid}, S) ->
    _ = join_rpc(N, Pid),
    {noreply, S};

handle_cast(_, S) ->
    {noreply, S}.

handle_info({'DOWN', MonitorRef, process, Pid, _Info}, S) ->
    leave_rpc(MonitorRef, Pid),
    {noreply, S};

handle_info(_, S) ->
    {noreply, S}.

terminate(_Reason, _S) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%
%%% Local functions
%%%

join_rpc(N, Pid) ->
    MonitorRef = erlang:monitor(process, Pid),
    case ets:lookup(?TAB, {n, N}) of
        [{{n, N}, {Pid, MonitorRef}}] ->
            ok;
        [{{n, N}, {Pid, OldRef0}}] ->
            ets:update_element(?TAB, {n, N}, {2, {Pid, MonitorRef}}), 
            erlang:demonitor(OldRef0, [flush]);
        [{{n, N}, {OldPid, OldRef1}}] ->
            ets:update_element(?TAB, {n, N}, {2, {Pid, MonitorRef}}), 
            ets:delete(?TAB, {pid, OldPid}),
            erlang:demonitor(OldRef1, [flush]);
        _ ->
            ets:insert(?TAB, {{n, N}, {Pid, MonitorRef}})
    end,

    case ets:insert_new(?TAB, {{pid, Pid}, {N, MonitorRef}}) of
        true ->
            ok;
        false ->
            ets:update_element(?TAB, {pid, Pid}, {2, {N, MonitorRef}}) 
    end.

leave_rpc(MonitorRef, Pid) ->
    case ets:lookup(?TAB, {pid, Pid}) of
        [{{pid, Pid}, {N, MonitorRef}}] ->
            true = ets:delete(?TAB, {pid, Pid}),
            true = ets:delete(?TAB, {n, N}),
            true = erlang:demonitor(MonitorRef, [flush]);
        _ ->
            error_logger:error_info("unknown died ! MonitorRef : ~p Pid : ~p~n", [MonitorRef, Pid]),
            ok
    end.

ensure_started() ->
    case whereis(?MODULE) of
        undefined ->
            webmqx_sup:start_restartable_child(?MODULE);
        _Pid ->
            ok
    end.
