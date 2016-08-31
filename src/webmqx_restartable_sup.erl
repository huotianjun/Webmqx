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
%% Copyright (c) 2007-2015 Pivotal Software, Inc.  All rights reserved.
%%

-module(webmqx_restartable_sup).

-behaviour(supervisor2).

-export([start_link/3]).

-export([init/1]).

-include_lib("rabbit_common/include/rabbit.hrl").

-define(DELAY, 2).

%%----------------------------------------------------------------------------

-ifdef(use_specs).
-endif.

%%----------------------------------------------------------------------------
%%
%%huotianjun 本节点在webmqx_sup下, 把可以重启的children都放到这里. 因为webmqx_sup的节点是one_for_all的，把需要one_for_one的都放到这里
%%huotianjun 一个sup下面只有一个child
start_link(Name, {_M, _F, _A} = Fun, Delay) ->
    supervisor2:start_link({local, Name}, ?MODULE, [Fun, Delay]).

init([{Mod, _F, _A} = Fun, Delay]) ->
    {ok, {{one_for_one, 10, 10},
          [{Mod, Fun, case Delay of
                          true  -> {transient, 1};
                          false -> transient
                      end, ?MAX_WAIT, worker, [Mod]}]}}.
