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

%%huotianjun
amqp_connect(ConnName) ->
    RabbitUserBin   = env(default_user),
    RabbitPassBin   = env(default_pass),
	AdapterInfo = #amqp_adapter_info{
						additional_info = [
											{channels, 1},
											{channel_max, 1},
											{frame_max, 0},
											{client_properties,
												[{<<"product">>, longstr, <<"RPC client">>}]}] 
					},

	case amqp_login(ConnName, RabbitUserBin, RabbitPassBin, AdapterInfo) of
		{ok, Conn, _VHost} ->
			link(Conn),

			{ok, Conn}; 
		ConnAck ->
			{error, ConnAck}
    end.

%%huotianjun 与rabbitmq server 连接
amqp_login(ConnName, UserBin, PassBin, AdapterInfo) ->
	%%huotianjun vhost或者在env里面定义，或者在usrbin里面描述
    {VHost, UsernameBin} = get_vhost_username(UserBin),
	%%huotianjun direct连接
	%%huotianjun 注意：这个start最终跑到了amqp_direct_connection的connect，没有用到这个adapter_info信息？直接rpc call Node的rabbit_direct的connect了
	%%
	%%huotianjun 为什么会跑到direct，是因为这个amqp_params_direct结构
	%%huotianjun 如果是#amqp_params_network{}，会采用网络方式间接rabbitmq server
	%%
	%%-record(amqp_params_direct, {username          = none,
	%%                             password          = none,
	%							   virtual_host      = <<"/">>,
	%%                             node              = node(),
	%%							   adapter_info      = none,
	%%                             client_properties = []}).
	%%
    case amqp_connection:start(#amqp_params_direct{
                                  username     = UsernameBin,
                                  password     = PassBin,
                                  virtual_host = VHost,
								  node		   = env(rabbit_node),
                                  adapter_info = AdapterInfo}, ConnName) of
		%%huotianjun 连接是不管校验的
        {ok, Connection} ->
			%%huotianjun 这个User是#auth_user{} ???
			%%{ok, _User} = rabbit_access_control:check_user_login(
            %%                     UsernameBin,
            %%                     case PassBin of
            %%                       none -> [];
            %%                       P -> [{password,P}]
            %%                     end),
			{ok, Connection, VHost};
        Error0 = {error, {auth_failure, Explanation}} ->
            hello_log:error("AMQP login failed for ~p auth_failure: ~s~n",
                             [binary_to_list(UserBin), Explanation]),
            Error0;
        Error1 = {error, access_refused} ->
            hello_log:warning("AMQP login failed for ~p access_refused "
                               "(vhost access not allowed)~n",
                               [binary_to_list(UserBin)]),
            Error1 
    end.

get_vhost_username(UserBin) ->
    Default = {env(vhost), UserBin},
    case application:get_env(?APP, ignore_colons_in_username) of
        {ok, true} -> Default;
        _ ->
            %% split at the last colon, disallowing colons in username
            case re:split(UserBin, ":(?!.*?:)") of
                [Vhost, UserName] -> {Vhost,  UserName};
                [UserBin]         -> Default
            end
    end.

%%huotianjun 获取rpc的通道数量
get_rpc_clients_count(DefaultCount) when is_number(DefaultCount) ->
    case application:get_env(?APP, count_of_rpc_clients) of
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
  list_to_atom("retained_" ++ hello_misc:format("~36.16.0b", [Num])).
