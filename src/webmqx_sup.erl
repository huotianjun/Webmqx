%%
%% This is the version of rabbit_sup from RabbitMQ.
%%   

-module(webmqx_sup).
-behaviour(supervisor2).

%% API.
-export([start_link/0, 
         start_supervisor_child/1, start_supervisor_child/2,
         start_supervisor_child/3,
         start_restartable_child/1, start_restartable_child/2, start_restartable_child/4,
         start_delayed_restartable_child/1, start_delayed_restartable_child/2
         ]).

%% supervisor.
-export([init/1]).

-include_lib("rabbit_common/include/rabbit.hrl").

-define(SERVER, ?MODULE).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(start_link/0 :: () -> rabbit_types:ok_pid_or_error()).
-spec(start_supervisor_child/1 :: (atom()) -> 'ok').
-spec(start_supervisor_child/2 :: (atom(), [any()]) -> 'ok').
-spec(start_supervisor_child/3 :: (atom(), atom(), [any()]) -> 'ok').
-spec(start_restartable_child/1 :: (atom()) -> 'ok').
-spec(start_restartable_child/2 :: (atom(), atom(), [any()], boolean()) -> 'ok').
-spec(start_restartable_child/4 :: (atom(), [any()]) -> 'ok').
-spec(start_delayed_restartable_child/1 :: (atom()) -> 'ok').
-spec(start_delayed_restartable_child/2 :: (atom(), [any()]) -> 'ok').

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported functions
%%%

start_link() ->
	supervisor2:start_link({local, ?MODULE}, ?MODULE, []).

start_supervisor_child(Mod) -> start_supervisor_child(Mod, []).

start_supervisor_child(Mod, Args) -> start_supervisor_child(Mod, Mod, Args).

start_supervisor_child(ChildId, Mod, Args) ->
    child_reply(supervisor2:start_child(
                  ?SERVER,
                  {ChildId, {Mod, start_link, Args},
                   transient, infinity, supervisor, [Mod]})).

start_restartable_child(M)            -> start_restartable_child(M, M, [], false).
start_restartable_child(M, A)         -> start_restartable_child(M, M, A,  false).
start_delayed_restartable_child(M)    -> start_restartable_child(M, M, [], true).
start_delayed_restartable_child(M, A) -> start_restartable_child(M, M, A,  true).

start_restartable_child(Name0, Mod, Args, Delay) ->
    Name = list_to_atom(atom_to_list(Name0) ++ "_sup"),
    child_reply(supervisor2:start_child(
                  ?SERVER,
                  {Name, {webmqx_restartable_sup, start_link,
                          [Name, {Mod, start_link, Args}, Delay]},
                   transient, infinity, supervisor, [webmqx_restartable_sup]})).

%%%
%%% Callback of supervisor
%%%

init([]) -> {ok, {{one_for_all, 0, 1}, []}}.

%%%
%%% Local functions
%%%
child_reply({ok, _}) -> ok;
child_reply(X)       -> X.
