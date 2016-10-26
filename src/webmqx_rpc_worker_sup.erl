-module(webmqx_rpc_worker_sup).

-behaviour(supervisor2).

-include("webmqx.hrl").

-export([start_link/0]).
-export([init/1]).
-export([flush_routing_ring/1]).

-include_lib("rabbit_common/include/rabbit.hrl").

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(start_link/0 :: () -> rabbit_types:ok(pid())).

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported function
%%%

start_link() ->
    {ok, SupPid} = supervisor2:start_link(?MODULE, []),
	{ok, SupPid}.

flush_routing_ring(WordsOfPath) ->
	[begin
			webmqx_rpc_worker:flush_routing_ring(Pid, WordsOfPath)
		end || {_ProcessName, Pid, _Type, [_Class]} <- supervisor:which_children(?MODULE)].

%%%
%%% Callback of supervisor
%%%

init([]) -> 
	Procs = [
		{{webmqx_rpc_worker, N}, {webmqx_rpc_worker, start_link, [N]},
			permanent, 16#ffffffff, worker, []}
			|| N <- lists:seq(1, webmqx_util:env_rpc_workers_num())],
	{ok, {{one_for_one, 1, 5}, Procs}}.

