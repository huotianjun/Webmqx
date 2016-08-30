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

%%huotianjun 分离url里面的path
split_path(<< $/, Path/bits >>) ->
	split_path(Path, []);
split_path(_) ->
	badrequest.

%%huotianjun 这个是个经典的字符串分段分析
%%huotianjun 分离出的结果，就用倒序的
%%huotianjun 相应的配合：routes从数据库中取出来，key是split path的lists，就设成倒序的！！
split_path(Path, Acc) ->
	try
		case binary:match(Path, <<"/">>) of
			nomatch when Path =:= <<>> ->
				%%huotianjun 没有了，整理输出
				[cow_qs:urldecode(S) || S <- Acc];
			nomatch ->
				%%huotianjun 最后一段了，整理输出
				%%huotianjun 需要多url中的转义码进行恢复
				[cow_qs:urldecode(S) || S <- [Path|Acc]];
			{Pos, _} ->
				<< Segment:Pos/binary, _:8, Rest/bits >> = Path,
				split_path(Rest, [Segment|Acc])
		end
	catch
		error:badarg ->
			badrequest
	end.

amqp_close(undefined) ->
    ok;
amqp_close(Connection) ->
    %% ignore noproc or other exceptions to avoid debris
    catch amqp_connection:close(Connection),
	ok.

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
