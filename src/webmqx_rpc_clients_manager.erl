-module(web_rpc_clients_manager).
-behaviour(gen_server2).

-export([join/2, get_rpc_pid/0]).
-export([sync/0]). %% intended for testing only; not part of official API
-export([start/0, start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2]).

%%----------------------------------------------------------------------------
%%
-define(TAB, rpc_client_table).

-ifdef(use_specs).

-endif.

%%----------------------------------------------------------------------------

%%huotianjun 这个进程是管理rpc client的数据字典, 与webmqx_rpc_clients_manager配合使用
%%huotianjun 集中维护，通过ets提供分散查询

%%%
%%% Exported functions
%%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%huotianjun 用这个启动, 目的是让?TAB的new在start_link之外执行，避免节点重启的时候，重新new
start() ->
	%%huotianjun 创建全局table
	?TAB = ets:new(?TAB, [
		ordered_set, public, named_table]),
    ensure_started().

%%huotianjun 只进不正常出，只有在Pid退出后，才从这里捕捉到，退出
join(N, Pid) when is_pid(Pid) ->
    gen_server2:cast(?MODULE, {join, N, Pid}).

%%huotianjun 用Req进程的进程id随机生成一个N，得到rpc client，确保均衡分布
get_rpc_pid() ->
	%%huotianjun 随机取一个rpc client编号，默认100
	Count = webmqx_util:get_rpc_clients_count(100),
	%%huotianjun 这个是被webmqx_handler调用的, 每个req进程一个self()
	N = erlang:phash2(self(), Count) + 1,
	%%error_logger:info_msg("N : ~p~n", [N]),
	get_rpc_pid(N, undefined, undefined).

%%huotianjun 如果没有命中，看下一个，找到为止
get_rpc_pid(_N, C, _) when C =/= undefined andalso C =< 0 ->
	undefined;
get_rpc_pid(N, C, Count) ->
	case ets:lookup(?TAB, {n, N}) of
		[{{n, N}, {Pid, _Ref}}] ->
			{ok, Pid};
		_ ->
			case C of
				undefined ->
					%%huotianjun 第一次没找到，那么最多再找Count0次, 保留住
					Count0 = webmqx_util:get_rpc_clients_count(100),
					get_rpc_pid(case N+1 > Count0 of true -> 1; false -> N+1 end, Count0 - 1, Count0);
				_ ->
					get_rpc_pid(case N+1 > Count of true -> 1; false -> N+1 end, C - 1, Count)
			end
	end.

sync() ->
    gen_server:call(?MODULE, sync, infinity).

%%%
%%% Callback functions from gen_server
%%%

-record(state, {}).

init([]) ->
	%%huotianjun 重启的时候，把之前的内容重新join一下。主要是需要重新monitor，Ref也变了
	[join_rpc(N, Pid) ||
		[N, {Pid, _Ref}] <- ets:match(?TAB, {{n, '$1'}, '$2'})],
    {ok, #state{}}.

handle_call(sync, _From, S) ->
    {reply, ok, S};

handle_call(Request, From, S) ->
    error_logger:warning_msg("The rpc_local server received an unexpected message:\n"
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

%%%
%%% Local functions
%%%

join_rpc(N, Pid) ->
	%%error_logger:info_msg("join_rpc : ~p ~p~n", [N, Pid]),
	MonitorRef = erlang:monitor(process, Pid),
	case ets:lookup(?TAB, {n, N}) of
		[{{n, N}, {Pid, MonitorRef}}] ->
			%%huotianjun 同一个Pid，monitor多次，Ref是不同的
			%%huotianjun 所以，这种情况不存在
			ok;
		[{{n, N}, {Pid, OldRef0}}] ->
			%%huotianjun 本进程重启，会出现这个情况
			erlang:demonitor(OldRef0, [flush]),
			ets:update_element(?TAB, {n, N}, {2, {Pid, MonitorRef}}); 
		[{{n, N}, {OldPid, OldRef1}}] ->
			erlang:demonitor(OldRef1, [flush]),
			ets:update_element(?TAB, {n, N}, {2, {Pid, MonitorRef}}), 
			ets:delete(?TAB, {pid, OldPid});
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
			error_logger:info_msg("leave_rpc : ~p ~p~n", [N, Pid]),

			true = erlang:demonitor(MonitorRef, [flush]),
            true = ets:delete(?TAB, {pid, Pid}),
            true = ets:delete(?TAB, {n, N});
		_ ->
			error_logger:error_info("unknown died ! MonitorRef : ~p Pid : ~p~n", [MonitorRef, Pid]),
            ok
    end.

ensure_started() ->
    case whereis(?MODULE) of
        undefined ->
			webmqx_sup:start_restartable_child(?MODULE);
        Pid ->
            {ok, Pid}
    end.
