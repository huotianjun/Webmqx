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

-module(webmqx_util).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("webmqx.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

%%huotianjun 获取rpc的通道数量
get_rpc_channel_count(DefaultCount) when is_number(DefaultCount) ->
    case application:get_env(?APP, count_of_rpc_channel) of
        {ok, C} -> C;
        _ -> DefaultCount
	end.

env(Key) ->
    case application:get_env(?APP, Key) of
        {ok, Val} -> Val;
        undefined -> undefined
    end.

path_for(Dir, VHost) ->
  filename:join(Dir, vhost_name_to_dir_name(VHost)).

path_for(Dir, VHost, Suffix) ->
  filename:join(Dir, vhost_name_to_dir_name(VHost, Suffix)).

vhost_name_to_table_name(VHost) ->
  <<Num:128>> = erlang:md5(VHost),
  list_to_atom("retained_" ++ rabbit_misc:format("~36.16.0b", [Num])).
