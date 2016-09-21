-module(webmqx_handler).

%% Standard callbacks.
-export([init/2]).

%%%
%%% Callback of cowboy
%%%

init(Req , Opts) ->

	#{rpc_workers_num := WorkersNum} = Opts,

	{ok, {_Host, Path, Method, PayloadJson, Req2}} = req_parse(Req),

	IsConsistentReq = case Method of
						<<"GET">>		-> false;
						<<"POST">>		-> false;
						<<"PUT">>		-> true;
						<<"DELETE">>	-> true;
						_				-> false
					end,

	Response =
	try 
		case webmqx_rpc_worker_manager:get_a_worker(WorkersNum) of
			undefined -> {error, #{}, <<"">>};
			{ok, RpcWorkerPid} ->
				case IsConsistentReq of
					true ->
						case webmqx_rpc_worker:normal_publish(RpcWorkerPid, Path, PayloadJson) of
							ok ->	
								{ok, #{}, <<>>};
							_ ->
								{error, #{},  <<"normal_publish error">>}
						end;
					false ->	
						case webmqx_rpc_worker:rpc(sync, RpcWorkerPid, Path, PayloadJson) of
							undefined ->
								{error, #{}, <<"rpc_sync error">>};
							{ok, R} -> 
								%%#{<<"headers">> := #{<<"host">> := Host, <<"method">> := Method, <<"path">> := Path, <<"qs">> := Qs},     <<"body">> := Body}
							   	R1= jiffy:decode(R, [return_maps]),	
								error_logger:info_msg("test jiffy decode response", [R1]),
								{ok, Header, Body}
						end
				end
		end
	catch 
		_Error:_Reason -> 
			{error, #{}, <<"rpc crash">>} 
	end,

	cowboy_req:reply(200, #{
				<<"content-type">> => <<"text/html">>
				}, <<"ok">>, Req2),

	%%http_reply(Response),

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

	{ok, {Host, Path, Method, jiffy:encode(Payload), Req2}}.

http_reply(error, Headers, Body) ->
	Path = cowboy_req:path(Req),
	Body = ["404 Not Found: \"", Path,
				"\" is not the path you are looking for.\n"],
	Headers2 = lists:keyreplace(<<"content-length">>, 1, Headers,
									{<<"content-length">>, integer_to_list(iolist_size(Body))}),
	cowboy_req:reply(404, Headers2, Body, Req).



