-module(web_rpc_channel_manager).
-behaviour(gen_server2).

-include("webmqx.hrl").

-export([join/2, get_rpc_channel_pid/0]).
-export([sync/0]). %% intended for testing only; not part of official API
-export([start/0, start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2]).

%%----------------------------------------------------------------------------
%%
-define(TAB, rpc_channel_table).

-ifdef(use_specs).

-endif.

%%----------------------------------------------------------------------------

%%huotianjun 这个进程是管理rpc channel的ets
%%huotianjun 集中维护，通过ets提供分布查询

%%%
%%% Exported functions
%%%
start_link() ->
    gen_server2:start_link({local, ?MODULE}, ?MODULE, [], []).

%%huotianjun 用这个启动, 目的是让?TAB的new在start_link之外执行，避免节点重启时候new
start() ->
	%%huotianjun 创建全局table
	?TAB = ets:new(?TAB, [
		ordered_set, public, named_table]),
    ensure_started().

join(N, Pid) when is_pid(Pid) ->
    gen_server2:cast(?MODULE, {join, N, Pid}).

%%huotianjun 用Req进程的进程id随机生成一个N，均衡调用
get_rpc_channel_pid() ->
	Count = webmqx_util:get_rpc_channel_count(?DEFAULT_RPC_CHANNEL_MAX),

	%%huotianjun 这个是被webmqx_handler调用的, 每个req一个独立进程
	N = erlang:phash2(self(), Count) + 1,
	get_rpc_channel_pid(N, {undefined, undefined}).

%%huotianjun 如果没有命中，看下一个，找到为止
get_rpc_channel_pid1(_N, {C, _}) when C =/= undefined andalso C =< 0 ->
	undefined;
get_rpc_channel_pid1(N, {C, Count}) ->
	case ets:lookup(?TAB, {n, N}) of
		[{{n, N}, {Pid, _Ref}}] ->
			{ok, Pid};
		_ ->
			case C of
				undefined ->
					%%huotianjun 第一次没找到，设置继续找的上下文
					Count0 = webmqx_util:get_rpc_channel_count(?DEFAULT_RPC_CHANNEL_MAX),
					get_rpc_channel_pid1(case N+1 > Count0 of true -> 1; false -> N+1 end, {Count0 - 1, Count0});
				_ ->
					get_rpc_channel_pid1(case N+1 > Count of true -> 1; false -> N+1 end, {C - 1, Count})
			end
	end.

sync() ->
    gen_server2:call(?MODULE, sync, infinity).

%%%
%%% Callback functions from gen_server
%%%

-record(state, {}).

init([]) ->
	%%huotianjun 重启的时候，把之前的内容重新join一下。Ref变了
	[join_rpc(N, Pid) ||
		[N, {Pid, _Ref}] <- ets:match(?TAB, {{n, '$1'}, '$2'})],
    {ok, #state{}}.

handle_call(sync, _From, S) ->
    {reply, ok, S};

handle_call(Request, From, S) ->
    error_logger:warning_msg("The rpc channel manager server received an unexpected message:\n"
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
	MonitorRef = erlang:monitor(process, Pid),
	case ets:lookup(?TAB, {n, N}) of
		[{{n, N}, {Pid, MonitorRef}}] ->
			%%huotianjun 同一个Pid，monitor多次，Ref是不同的
			%%huotianjun 所以，这种情况不存在
			ok;
		[{{n, N}, {Pid, OldRef0}}] ->
			%%huotianjun 本进程重启，会出现这个情况
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
			%%error_logger:info_msg("leave_rpc : ~p ~p~n", [N, Pid]),

            true = ets:delete(?TAB, {pid, Pid}),
            true = ets:delete(?TAB, {n, N});
			true = erlang:demonitor(MonitorRef, [flush])
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
