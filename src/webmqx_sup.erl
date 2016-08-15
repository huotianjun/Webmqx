%% 

%% @private
-module(webmqx_sup).
-behaviour(supervisor2).

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
	supervisor2:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Mod) -> start_child(Mod, []).

start_child(Mod, Args) -> start_child(Mod, Mod, Args).

start_child(ChildId, Mod, Args) ->
    child_reply(supervisor2:start_child(
                  ?SERVER,
                  {ChildId, {Mod, start_link, Args},
                   transient, ?WORKER_WAIT, worker, [Mod]})).

start_supervisor_child(Mod) -> start_supervisor_child(Mod, []).

start_supervisor_child(Mod, Args) -> start_supervisor_child(Mod, Mod, Args).

start_supervisor_child(ChildId, Mod, Args) ->
    child_reply(supervisor2:start_child(
                  ?SERVER,
                  {ChildId, {Mod, start_link, Args},
                   transient, infinity, supervisor, [Mod]})).

start_restartable_child(M)            -> start_restartable_child(M, [], false).
start_restartable_child(M, A)         -> start_restartable_child(M, A,  false).
start_delayed_restartable_child(M)    -> start_restartable_child(M, [], true).
start_delayed_restartable_child(M, A) -> start_restartable_child(M, A,  true).

start_restartable_child(Mod, Args, Delay) ->
    Name = list_to_atom(atom_to_list(Mod) ++ "_sup"),
    child_reply(supervisor2:start_child(
                  ?SERVER,
                  {Name, {webmqx_restartable_sup, start_link,
                          [Name, {Mod, start_link, Args}, Delay]},
                   transient, infinity, supervisor, [webmqx_restartable_sup]})).

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
