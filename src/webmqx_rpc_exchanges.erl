-module(webmqx_rpc_exchanges).

-export([init/0, search_exchange/3]).


%%huotianjun 把Exchanges设置到ranch core opts中
set_ranch_opts_routingkeys(HostExchanges) ->
	Opts = #{env => #{rpc_router = RPCRouter}} = ranch_server:get_protocol_options(http),
	Opts1 = Opts#{env => #{rpc_router = RPCRouter}},
	ok = ranch_server:set_protocol_options(http, Opts1).

%%huotianjun 注意：exchanges从数据库中取出来，key是split path的lists，就设成倒序的！！ 设置到HostExchanges中
%%huotianjun HostExchanges放置到ranch core Opts map中
%%
search_exchange(Host, Path, HostExchanges) when is_binary(Path) ->
	SplitPath = webmqx_util:split_path(Path),
	search_exchange(Host, SplitPath, HostExchanges);

search_exchange(Host, SplitPath, HostExchanges)  ->
	case dict:find(Host, HostExchanges) of 
		{ok, Exchanges} -> search_exchange1(SplitPath, Exchanges);
		_ -> undefined 
	end.

search_exchange1([], Exchanges) ->
	case dict:find([<<"/">>], Exchanges) of 
		{ok, Exchange} ->
			{ok, Exchange};
		_ ->
			undefined
	end;

search_exchange1(SplitPath = [_|Rest] , Exchanges) ->
	case dict:find(SplitPath, Exchanges) of
		{ok, Exchange} ->
			{ok, Exchange};
		_ ->
			search_exchange1(Rest, Exchanges) 
	end.
