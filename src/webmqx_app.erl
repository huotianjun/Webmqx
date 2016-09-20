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
%% The Initial Developer of the Original Code is VMware, Inc.
%% Copyright (c) 2007-2011 VMware, Inc.  All rights reserved.
%%

-module(webmqx_app).
-behaviour(application).

-include_lib("rabbit_common/include/rabbit.hrl").

-export([start/2]).
-export([stop/1]).

%%%
%%% Callbacks of application
%%%

start(_Type, _Args) ->
	Result = webmqx_sup:start_link(),

	webmqx_rpc_worker_manager:start(),
	webmqx_exchange_routing:start(),
	webmqx_service_internal:start(),

	webmqx_sup:start_supervisor_child(webmqx_rpc_worker_sup),
	webmqx_sup:start_supervisor_child(webmqx_consistent_req_sup),

	Dispatch = cowboy_router:compile([
		{'_', [
			{'_', webmqx_handler, []}
		]}
	]),

	{ok, _Cowboy} = cowboy:start_clear(http, 100, [{port, 80}], 
		#{env => #{dispatch => Dispatch}} 
	),

	EventPid = case rabbit_event:start_link() of
					{ok, Pid}                       -> Pid;
					{error, {already_started, Pid}} -> Pid
				end,
	gen_event:add_handler(EventPid, webmqx_binding_event_handler, []),

	Result.

stop(_State) ->
	ok.
