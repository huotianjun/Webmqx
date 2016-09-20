-module(webmqx_handler).

%% Standard callbacks.
-export([init/2]).

%%%
%%% Callback of cowboy
%%%

init(Req , Opts) ->
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
		case webmqx_rpc_worker_manager:get_a_worker() of
			undefined -> <<"ERROR">>;
			{ok, RpcChannelPid} ->
				case IsConsistentReq of
					true ->
						case webmqx_rpc_worker:normal_publish(RpcChannelPid, Path, PayloadJson) of
							ok ->	
								<<"OK">>;
							_ ->
								<<"ERROR:normal_publish">>
						end;
					false ->	
						case webmqx_rpc_worker:rpc(sync, RpcChannelPid, Path, PayloadJson) of
							undefined ->
								<<"ERROR:rpc_sync">>;
							{ok, Response1} -> 
								Response1
						end
				end
		end
	catch 
		_Error:_Reason -> 
			<<"ERROR:rpc crash">> 
	end,

	cowboy_req:reply(200, #{
				<<"content-type">> => <<"text/html">>
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

	{ok, {Host, Path, Method, jiffy:encode(Payload), Req2}}.

