-module(webmqx_http_handler).

%% Standard callbacks.
-export([init/2]).

%%%
%%% Callback of cowboy
%%%

init(Req , Opts) ->
	#{rpc_workers_num := WorkersNum} = Opts,
	{ok, {ClientIP, _Host, Path, Method, PayloadJson, Req2}} = req_parse(Req),
	IsConsistentReq = is_consistent_req(Method),

	Response =
	try 
		case webmqx_rpc_worker_manager:get_a_worker(WorkersNum) of
			undefined -> {error, #{}, <<"">>};
			{ok, RpcWorkerPid} ->
				case IsConsistentReq of
					true ->
						case webmqx_rpc_worker:consistent_publish(RpcWorkerPid, ClientIP, Path, PayloadJson) of
							ok ->	
								{ok, #{}, <<>>};
							_ ->
								{error, #{},  <<"consistent_publish error">>}
						end;
					false ->	
						case webmqx_rpc_worker:rpc(sync, RpcWorkerPid, ClientIP, Path, PayloadJson) of
							undefined ->
								{error, #{}, <<"rpc_sync error">>};
							{ok, R} -> 
								#{<<"headers">> := Headers, <<"body">> := Body}
									= jiffy:decode(R, [return_maps]),	
								{ok, Headers, Body}
						end
				end
		end
	catch 
		_Error:_Reason -> 
			{error, #{}, <<"rpc crash">>} 
	end,

	http_reply(Response, Req2),

	{ok, Req2, Opts}.

req_parse(Req) ->
	Host = cowboy_req:host(Req),
	Method = cowboy_req:method(Req),
	Path = cowboy_req:path(Req),
	Qs = cowboy_req:qs(Req),
	{PeerIP, _} = cowboy_req:peer(Req),

	{Body, Req2}  = 
		case cowboy_req:has_body(Req) of
			true -> 
				case cowboy_req:read_body(Req, #{ 
												length => 64000,
												read_length => 64000,
												read_timeout => 5000}) of
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

	{ok, {PeerIP, Host, Path, Method, jiffy:encode(Payload), Req2}}.

is_consistent_req(<<"GET">>) -> false;
is_consistent_req(<<"POST">>) -> false;
is_consistent_req(<<"PUT">>) -> true;
is_consistent_req(<<"DELETE">>) -> true;
is_consistent_req(_) -> false.

http_reply({error, Headers, Body}, Req) ->
	Headers2 = Headers#{<<"content-length">> => integer_to_list(iolist_size(Body))}, 
	cowboy_req:reply(404, Headers2, Body, Req);

http_reply({ok, Headers, Body}, Req) ->
	Headers2 = Headers#{<<"content-length">> => integer_to_list(iolist_size(Body))}, 
	cowboy_req:reply(200, Headers2, Body, Req).

