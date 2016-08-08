%% Feel free to use, reuse and abuse the code in this file.

%% @private
-module(webmqx_sup).
-behaviour(supervisor).

%% API.
-export([start_link/0, start_child/1, start_child/2, start_child/3,
         start_supervisor_child/1, start_supervisor_child/2,
         start_supervisor_child/3,
         start_restartable_child/1, start_restartable_child/2,
         start_delayed_restartable_child/1, start_delayed_restartable_child/2,
         stop_child/1]).

%% supervisor.
-export([init/1]).

-include_lib("rabbit_common/include/rabbit.hrl").

-define(SERVER, ?MODULE).

%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
	%%huotianjun 应用总根
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%huotianjun 这个child是在总根下创建的
%%
%%huotianjun 头两个调用方法，只有一个这样Mod的child
start_child(Mod) -> start_child(Mod, []).

start_child(Mod, Args) -> start_child(Mod, Mod, Args).

%%huotianjun 这种调法，一个Mod可以有多个child，但是ChildId必须不同
start_child(ChildId, Mod, Args) ->
    child_reply(supervisor:start_child(
                  ?SERVER,
                  {ChildId, {Mod, start_link, Args},
                   transient, ?WORKER_WAIT, worker, [Mod]})).

%%huotianjun 二级枝
start_supervisor_child(Mod) -> start_supervisor_child(Mod, []).

start_supervisor_child(Mod, Args) -> start_supervisor_child(Mod, Mod, Args).

start_supervisor_child(ChildId, Mod, Args) ->
    child_reply(supervisor:start_child(
                  ?SERVER,
                  {ChildId, {Mod, start_link, Args},
                   transient, infinity, supervisor, [Mod]})).

start_restartable_child(M)            -> start_restartable_child(M, [], false).
start_restartable_child(M, A)         -> start_restartable_child(M, A,  false).
start_delayed_restartable_child(M)    -> start_restartable_child(M, [], true).
start_delayed_restartable_child(M, A) -> start_restartable_child(M, A,  true).

%%huotianjun 一个二级枝加一个child
start_restartable_child(Mod, Args, Delay) ->
	%%huotianjun 自动为这个child创建了一个sup
    Name = list_to_atom(atom_to_list(Mod) ++ "_sup"),
    child_reply(supervisor:start_child(
                  ?SERVER,
				  %%huotianjun 注意：实际启动的名字并不是hello_restartable_sup!!!而是与Name相关的
                  {Name, {hello_restartable_sup, start_link,
                          [Name, {Mod, start_link, Args}, Delay]},
                   transient, infinity, supervisor, [hello_restartable_sup]})).

stop_child(ChildId) ->
    case supervisor:terminate_child(?SERVER, ChildId) of
        ok -> supervisor:delete_child(?SERVER, ChildId);
        E  -> E
    end.

init([]) -> {ok, {{one_for_all, 0, 1}, []}}.


%%----------------------------------------------------------------------------

child_reply({ok, _}) -> ok;
child_reply(X)       -> X.
%% supervisor.
