%% Feel free to use, reuse and abuse the code in this file.

%% @doc Pastebin handler.
-module(webmqx_handler).

%% Standard callbacks.
-export([init/2]).

%%huotianjun 每一个请求会创建一个进程用这个init处理Request
init(Req , Opts) ->
	%%error_logger:info_msg("Req : ~p ~n", [Req]),

	%%huotianjun 解析Req
	{ok, {_Host, Path, Method, PayloadJson, Req2}} = req_parse(Req),

	IsConsistentReq = case Method of
				   <<"GET">> -> false;
				   <<"POST">> -> false;
				   <<"PUT">> -> true;
				   <<"DELETE">> -> true;
				   _ -> false
				end,

	Response =
	try 
		case webmqx_rpc_channel_manager:get_a_pid() of
			undefined -> <<"no rpc channel">>;
			{ok, RpcChannelPid} ->
				case IsConsistentReq of
					true ->
						case webmqx_rpc_channel:publish(RpcChannelPid, Path, PayloadJson) of
							ok ->	
								<<"OK">>;
							_ ->
								<<"ERROR">>
						end;
					false ->	
						case webmqx_rpc_channel:rpc(call, RpcChannelPid, Path, PayloadJson) of
							undefined ->
								<<"ERROR">>;
							{ok, Response1} -> 
								Response1
						end
				end
		end
	catch 
		_Error:Reason -> 
			Reason 
	end,

	cowboy_req:reply(200, #{
				<<"content-type">> => <<"text/html">>
				%%<<"content-type">> => <<"text/plain">>
				}, Response, Req2),

	{ok, Req2, Opts}.

req_parse(Req) ->
	Host = cowboy_req:host(Req),
	Method = cowboy_req:method(Req),
	Path = cowboy_req:path(Req),
	Qs = cowboy_req:qs(Req),
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

	{ok, {Host, Path, Method, jiffy:encode(Payload), Req2}}.

