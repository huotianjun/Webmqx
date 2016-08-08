-module(hello_core_service).

-export([start/0]).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-endif.

%%----------------------------------------------------------------------------

start() ->
	%%huotianjun 默认的入口Fun是start_link
	rabbit_sup:start_restartable_child(webmqx_rpc_server, [<<"core-service-1">>, <<"core-service">>, fun core_service/1]),
	ok.

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
