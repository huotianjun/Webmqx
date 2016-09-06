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

-module(webmqx_binding_event_handler).

-behaviour(gen_event).

-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).

init([]) ->
  {ok, []}.

handle_event({event, binding_add, {PathSplited, _X, _D, _Args}, _, _}, State) ->
  Path = webmqx_util:words_to_path(PathSplited),
  webmqx_put_req_sup:start_child(Path),
  {ok, State};
handle_event({event, binding_remove, {PathSplited, _X, _D, _Args}, _, _}, State) ->
  Path = webmqx_util:words_to_path(PathSplited),
  webmqx_put_req_sup:delete_child(Path),
  {ok, State};

handle_event(_Event, State) ->
  {ok, State}.

handle_call(_Request, State) ->
  {ok, State}.

handle_info(_Info, State) ->
  {ok, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
