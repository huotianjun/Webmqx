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

start(_Type, _Args) ->
	%%huotianjun 根
	webmqx_sup:start_link(),

	%%huotianjun 启动RPC channel的管理器，在ets表中维护rpc channel信息，并monitor。初始为空
	webmqx_rpc_channel_manager:start(),

	%%huotianjun 启动所有的RPC channel（发送端），并在RPC channel管理器上注册
	webmqx_sup:start_supervisor_child(webmqx_rpc_channel_sup),

	%%huotianjun 测试微服务
	%%huotianjun test1-1是server name，会记录在binding的routingkey上
	webmqx_rpc_server:start_link(<<"test1-1">>, <<"test1">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-1">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-2">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-3">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-4">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-5">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-6">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-7">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-8">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-9">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-10">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test2-11">>, <<"test2">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"test3-1">>, <<"test3">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"report-1">>, <<"report">>, fun tsung_report/1),

	%%huotianjun 启动核心微服务
	webmqx_core_service:start(),

	Dispatch = cowboy_router:compile([
		{'_', [
			%%huotianjun []是Opts，会传入toppage_handler
			%%{"/", toppage_handler, []},
			%%{"/[...]", hello_handler, []}
			{'_', webmqx_handler, []}
		]}
	]),

	{ok, Cowboy} = cowboy2:start_clear(http, 100, [{port, 80}], 
		%%huotianjun rpc_exchanges通过Opts，传到ranch内核。在内核中，启动应用进程时，rpc_exchanges再传给Req
		#{env => #{dispatch => Dispatch}}
	),

	%%huotianjun 初始化ranch 内核opts中的rpc_exchanges
	webmqx_rpc_exchanges:init(),

	{ok, Cowboy}.

%%huotianjun 测试微服务的回调
micro_service_test(PayloadJSON) -> PayloadJSON.

tsung_report(PayloadJSON) when is_binary(PayloadJSON) ->
	Payload = jiffy:decode(PayloadJSON, [return_maps]),
	tsung_report1(Payload).

tsung_report1(_Payload = #{<<"req">> := #{<<"host">> := _Host, <<"method">> := _Method, <<"path">> := Path, <<"qs">> := _Qs}, <<"body">> := _Body}) ->
	%%error_logger:info_msg("Payload map : ~p ~n", [Payload]),
	read_file(Path).

%%huotianjun 取到path的/，与/root/.tsung拼起来
read_file(<<"/", Name/binary>>) ->
	case file:read_file(filename:join(<<"/root/.tsung">>, Name)) of
		{ok, Binary} -> Binary;
		_ -> <<"no such file">>
	end.

stop(_State) ->
	ok.
