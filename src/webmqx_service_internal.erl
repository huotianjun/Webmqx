-module(webmqx_service_internal).

-export([start/0]).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-endif.

%%----------------------------------------------------------------------------

start() ->
	webmqx_sup:start_restartable_child(webmqx_rpc_server_internal, [<<"core-service">>, <<"core-service">>, fun core_service/1]),

	%%huotianjun 启动测试微服务
	%%huotianjun 第一个参数会记录在binding的arg信息里面
	webmqx_sup:start_restartable_child(webmqx_rpc_server_internal, [<<"test">>, <<"1/2/3">>, fun micro_service_test/1]),
	webmqx_sup:start_restartable_child(webmqx_rpc_server_internal, [<<"report">>, <<"report">>, fun tsung_report/1]),
	ok.

%%huotianjun core_service callbacks
core_service(PayloadEncode) when is_binary(PayloadEncode) ->
	Payload = jiffy:decode(PayloadEncode, [return_maps]),
	%%error_logger:info_msg("Payload map : ~p~n", [Payload]),
	core_service1(Payload).

core_service1(#{<<"req">> := #{<<"host">> := Host, <<"method">> := Method, <<"path">> := Path, <<"qs">> := Qs}, <<"body">> := Body}) ->
	%% huotianjun payload的map(先写出这个map，在jiffy里面试着encode，再decode）
	%% #{method => <<"route_add">>, content => [<<"101.200.162.101">>, <<"/test1/test2">>, <<"test2">>]}
	%% huotianjun payload的json
	%% <<"{\"method\":\"route_add\",\"content\":[\"101.200.162.101\",\"/test1/test2\",,\"test2\"]}">>
	%%
	%% curl -i -d '{"method":"route_add","content":["101.200.162.101","/test1/test2","test2"]}' 101.200.162.101:8080/core
	%% curl -i -v -L "101.200.162.101/test1/test2?q1=1&q2=2"
	%%
	error_logger:info_msg("Host : ~p Method : ~p Path : ~p Qs : ~p~nBody : ~p~n", [Host, Method, Path, Qs, Body]),
	core_service2(jiffy:decode(Body, [return_maps])).

core_service2(#{<<"method">> := <<"route_add">>, <<"content">> := [Host, Path, Port]}) ->
	error_logger:info_msg("method : route_add, content : ~p ~p ~p ~n", [Host, Path, Port]),
	%%
		
	<<"ok">>.

%%huotianjun test callbacks
micro_service_test(_PayloadJSON) -> <<"Hello World!">>. %%PayloadJSON.

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

