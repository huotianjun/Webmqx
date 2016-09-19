%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

%% @private
-module(webmqx_sup).
-behaviour(supervisor2).

%% API.
-export([start_link/0, 
         start_supervisor_child/1, start_supervisor_child/2,
         start_supervisor_child/3,
         start_restartable_child/1, start_restartable_child/2,
         start_delayed_restartable_child/1, start_delayed_restartable_child/2,
         stop_child/1]).

%% supervisor.
-export([init/1]).

-include_lib("rabbit_common/include/rabbit.hrl").

-define(SERVER, ?MODULE).

-ifdef(use_specs).

-spec(start_link/0 :: () -> rabbit_types:ok_pid_or_error()).
-spec(start_supervisor_child/1 :: (atom()) -> 'ok').
-spec(start_supervisor_child/2 :: (atom(), [any()]) -> 'ok').
-spec(start_supervisor_child/3 :: (atom(), atom(), [any()]) -> 'ok').
-spec(start_restartable_child/1 :: (atom()) -> 'ok').
-spec(start_restartable_child/2 :: (atom(), [any()]) -> 'ok').
-spec(start_delayed_restartable_child/1 :: (atom()) -> 'ok').
-spec(start_delayed_restartable_child/2 :: (atom(), [any()]) -> 'ok').

-endif.

%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
	supervisor2:start_link({local, ?MODULE}, ?MODULE, []).

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

init([]) -> {ok, {{one_for_all, 0, 1}, []}}.


%%----------------------------------------------------------------------------

child_reply({ok, _}) -> ok;
child_reply(X)       -> X.
%% supervisor.
