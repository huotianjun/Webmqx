-module(webmqx_service_internal).

-include("webmqx.hrl").

-export([start/0]).

%%%
%%% Exported function
%%%

start() ->
	%% TODO : for internal http request.
	webmqx_sup:start_restartable_child(core_service, webmqx_rpc_server, [<<"internal-service">>, <<"/internal">>, fun internal_service/1], false),

	%% Test : HelloWorld
	webmqx_sup:start_restartable_child(test, webmqx_rpc_server, [<<"test">>, <<"/test/HelloWorld">>, fun service_test/1], false),

	%% Tsung test report.
	webmqx_sup:start_restartable_child(report, webmqx_rpc_server, [<<"report">>, <<"/test/report">>, fun tsung_report/1], false),

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

%%%
%%% Callbacks of test. 
%%%

service_test(_Body) -> 
	reponse_to_json([{<<"content-type">>, <<"text/html">>}], <<"Hello World">>).

internal_service(PayloadEncode) when is_binary(PayloadEncode) ->
	Payload = jiffy:decode(PayloadEncode, [return_maps]),
	internal_service1(Payload).

%% TODO: http api of webmqx management command
%%
%% try like here:
%% curl -i -d '{"method":"list","content":"/test"}' http://localhost/internal
%%
internal_service1(#{<<"req">> := #{<<"host">> := _Host, <<"method">> := _HttpMethod, <<"path">> := _Path, <<"qs">> := _Qs}, <<"body">> := Body}) ->
	internal_service2(jiffy:decode(Body, [return_maps])).

internal_service2(#{<<"method">> := <<"list">>, <<"content">> := Path}) when is_binary(Path)->
	Queues = rabbit_exchange_type_webmqx:fetch_routing_queues(webmqx_util:env_vhost(), ?WEBMQX_EXCHANGE, webmqx_util:path_to_words(Path)), 
	ResultString = io_lib:format("~p", Queues),
	reponse_to_json([{<<"content-type">>, <<"text/html">>}], list_to_binary(ResultString));
internal_service2(#{<<"method">> := Method, <<"content">> := _}) ->
	reponse_to_json([{<<"content-type">>, <<"text/html">>}], <<"Unknown command : ",  Method/binary>>);

internal_service2(_) ->
	reponse_to_json([{<<"content-type">>, <<"text/html">>}], <<"Bad command format">>).

tsung_report(PayloadJSON) when is_binary(PayloadJSON) ->
	Payload = jiffy:decode(PayloadJSON, [return_maps]),
	tsung_report1(Payload).

tsung_report1(_Payload = #{<<"req">> := #{<<"host">> := _Host, <<"method">> := _Method, <<"path">> := Path, <<"qs">> := Qs}, <<"body">> := _Body}) ->
	error_logger:info_msg("http qs : ~p ~n", [Qs]),
	reponse_to_json([{<<"content-type">>, <<"text/html">>}], read_file(Path)).

read_file(<<"/", Name/binary>>) ->
	case file:read_file(filename:join(<<"/root/.tsung">>, Name)) of
		{ok, Binary} -> Binary;
		_ -> <<"no such file">>
	end.

