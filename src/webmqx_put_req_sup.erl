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
%% Copyright (c) 2007-2014 GoPivotal, Inc.  All rights reserved.
%%

-module(webmqx_put_req_sup).
-behaviour(supervisor2).

-export([start_link/1, init/1, start_child/2,start_child/1, child_for_path/1,
         delete_child/1]).

-define(ENCODING, utf8).

-ifdef(use_specs).
-spec(start_child/1 :: (binary()) -> supervisor2:startchild_ret()).
-spec(start_child/2 :: (term(), binary()) -> supervisor2:startchild_ret()).
-endif.

start_link() ->
  supervisor2:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Path) when is_binary(Path) ->
  case start_child1(Path) of
    {ok, Pid}                       -> Pid;
    {error, {already_started, Pid}} -> Pid
  end.

start_child1(Path) ->
  supervisor2:start_child(?MODULE,
    {binary_to_atom(Path, ?ENCODING),
      {webmqx_put_req_broker, start_link, [Path]},
      permanent, 60, worker, [webmqx_cast_msg_broker]}).

delete_child(Path) ->
  Id = binary_to_atom(Path, ?ENCODING),
  ok = supervisor2:terminate_child(?MODULE, Id),
  ok = supervisor2:delete_child(?MODULE, Id).

init([]) ->
  {ok, {{one_for_one, 5, 10}, []}}.

