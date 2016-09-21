-module(webmqx_service_internal).

-export([start/0]).

%%%
%%% Exported function
%%%

start() ->
	webmqx_sup:start_restartable_child(core_service, webmqx_rpc_server, [<<"core-service">>, <<"core-service">>, fun core_service/1], false),
	webmqx_sup:start_restartable_child(test, webmqx_rpc_server, [<<"test">>, <<"/1/2/3">>, fun micro_service_test/1], false),
	webmqx_sup:start_restartable_child(report, webmqx_rpc_server, [<<"report">>, <<"report">>, fun tsung_report/1], false),
	ok.

%%%
%%% Local functions
%%%

reponse_to_json(Headers, Body) -> 
	Response = {[
				{headers, {Headers}},
				{body, Body}
			]},
	jiffy:encode(Response).

mircro_service_test(Body) -> 
	reponse_to_json([{<<"content-type">>, <<"text/html">>}], Body).

core_service(PayloadEncode) when is_binary(PayloadEncode) ->
	Payload = jiffy:decode(PayloadEncode, [return_maps]),
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
		
	reponse_to_json([{<<"content-type">>, <<"text/html">>}], <<"ok">>).

tsung_report(PayloadJSON) when is_binary(PayloadJSON) ->
	Payload = jiffy:decode(PayloadJSON, [return_maps]),
	tsung_report1(Payload).

tsung_report1(_Payload = #{<<"req">> := #{<<"host">> := _Host, <<"method">> := _Method, <<"path">> := Path, <<"qs">> := _Qs}, <<"body">> := _Body}) ->
	%%error_logger:info_msg("Payload map : ~p ~n", [Payload]),
	reponse_to_json([{<<"content-type">>, <<"text/html">>}], read_file(Path)).

read_file(<<"/", Name/binary>>) ->
	case file:read_file(filename:join(<<"/root/.tsung">>, Name)) of
		{ok, Binary} -> Binary;
		_ -> <<"no such file">>
	end.

