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
	Result = webmqx_sup:start_link(),

	%%huotianjun start manager 
	webmqx_rpc_channel_manager:start(),

	%%huotianjun webmqx exchange routing queues manager
	webmqx_exchange_routing:start(),

	%%huotianjun start core internal rpc server
	webmqx_core_service:start(),

	%%huotianjun start all RPC channels, and regstry in manager
	webmqx_sup:start_supervisor_child(webmqx_rpc_channel_sup),

	webmqx_sup:start_supervisor_child(webmqx_consistent_req_sup),

	%%huotianjun 启动测试微服务
	%%huotianjun 第一个参数会记录在binding的arg信息里面
	webmqx_rpc_server:start_link(<<"test">>, <<"test1/2/3">>, fun micro_service_test/1), 
	webmqx_rpc_server:start_link(<<"report">>, <<"report">>, fun tsung_report/1),

	Dispatch = cowboy_router:compile([
		{'_', [
			%%huotianjun []是Opts，会传入toppage_handler
			%%{"/", toppage_handler, []},
			%%{"/[...]", webmqx_handler, []}
			{'_', webmqx_handler, []}
		]}
	]),

	{ok, _Cowboy} = cowboy:start_clear(http, 100, [{port, 80}], 
		#{env => #{dispatch => Dispatch}, 
		  middlewares => [cowboy_router, cowboy_handler]}
	),

	EventPid = case rabbit_event:start_link() of
					{ok, Pid}                       -> Pid;
					{error, {already_started, Pid}} -> Pid
				end,
	gen_event:add_handler(EventPid, webmqx_binding_event_handler, []),

	Result.

%%huotianjun 测试微服务的server's callback
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
