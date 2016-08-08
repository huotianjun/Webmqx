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

-module(webmqx_rpc_client_sup).

-behaviour(supervisor2).

-export([start_link/0]).

-export([init/1]).

-include_lib("rabbit_common/include/rabbit.hrl").

%%----------------------------------------------------------------------------

-ifdef(use_specs).
-endif.

%%----------------------------------------------------------------------------
start_link() ->
    {ok, SupPid} = supervisor2:start_link(?MODULE, []),
	error_logger:info_msg("webmqx_rpc_client_sup : ~p~n", [SupPid]),
	{ok, SupPid}.

init([]) -> 
	%%huotianjun 从env取rpc clients数量，默认100
	Count = webmqx_util:get_rpc_clients_count(100),

	Procs = [
		{{webmqx_rpc_client, N}, {webmqx_rpc_client, start_link, [N]},
			permanent, 16#ffffffff, worker, []}
			|| N <- lists:seq(1, Count)],
	{ok, {{one_for_one, 1, 5}, Procs}}.

