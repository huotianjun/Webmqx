%% Feel free to use, reuse and abuse the code in this file.

%% @doc Pastebin handler.
-module(webmqx_handler).

%% Standard callbacks.
-export([init/2]).

%%huotianjun 每一个请求会创建一个进程用这个init处理Request
%%huotianjun 注意:这个Opts是State，会传入cowboy_rest
init(Req , Opts) ->
	%%random:seed(os:timestamp()),
	%%error_logger:info_msg("Req : ~p ~n", [Req]),

	%%huotianjun 解析Req
	{ok, Host, Path, PayloadJson, Ports, Req2} = req_parse(Req),

	%%huotianjun 从Ports字典中，查找Port 
	{ok, Port} = webmqx_rpc_exchanges:search_exchange(Host, Path, Ports), 
	%%error_logger:info_msg("find exchange : ~p~n", [R]),

	Response =
		case webmqx_rpc_clients_manager:get_rpc_pid() of
			undefined -> <<"no rpc handlers">>;
			{ok, Pid} ->
				webmqx_rpc_client:call(Pid, Port, PayloadJson) 
		end,
	%%error_logger:info_msg("Response : ~p~n", [Response]),

	cowboy_req:reply(200, #{
			<<"content-type">> => <<"text/html">>
			%%<<"content-type">> => <<"text/plain">>
				}, Response, Req2),
	{ok, Req2, Opts}.

req_rpc_exchanges(#{rpc_exchanges := Exchanges}) ->
	Exchanges.

req_parse(Req) ->
	Host = cowboy_req:host(Req),
	Method = cowboy_req:method(Req),
	Path = cowboy_req:path(Req),
	Qs = cowboy_req:qs(Req),
	RpcPorts = req_rpc_exchanges(Req),
	{Body, Req2}  = 
		case cowboy_req:has_body(Req) of
			true -> 
				case cowboy_req:read_body(Req, [
												{length, 64000},
												{read_length, 64000},
												{read_timeout, 5000}]) of
					{ok, Body1, Req1} ->
						{Body1, Req1};
					{more, _, Req1} ->
						{<<"error:badlength">>, Req1}
				end;
			false -> {<<"">>, Req}
		end,
	Payload = {[
				{req, {[
						{host, Host},
						{method, Method},
						{path, Path},
						{qs, Qs}	
					  ]}}, 
				{body, Body}
			   ]}, 

	%%error_logger:info_msg("Payload : ~p ~n", [Payload]),

	{ok, Host, Path, jiffy:encode(Payload), RpcPorts, Req2}.

