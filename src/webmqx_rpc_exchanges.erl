-module(webmqx_rpc_exchanges).

-export([init/0, search_exchange/3]).

%%huotianjun path是{Host, Path}
-record(rpc_path_exchange, {path, exchange}).

-define(TABLE, rpc_path_exchange).

%%huotianjun 定义rpc_exchanges表结构
-define(TABLE_DEFINE, {?TABLE, [{record_name, rpc_path_exchange},
								{disc_copies, [node()]},
								{attributes, record_info(fields, rpc_path_exchange)}]}).

%%huotianjun 把这个加入了table描述的attributes里面了？
-define(TABLE_MATCH, {match, #rpc_path_exchange { _ = '_' }}).

init() ->
	%%huotianjun rpc exchanges初始化时由这里加进去
	%%huotianjun 运行中可触发变动，通过ranch_server:set_protocol_opts，它可以自动通知内核变动！！！
	HostExchanges = dict:new(),
	Exchanges = dict:new(),

	%%huotianjun 注意：在exchagnes的数据库中，key是<<"/test1/test2/test3">>，取出来后，在应用dict中的key转换为：[<<"test3">>, <<"test2">>, <<"test1">>]。根是特殊的：[<<"/">>]
	Exchanges1 = dict:store([<<"/">>], <<"stock">>, Exchanges),

	Exchanges2 = dict:store([<<"test1">>], <<"test1">>, Exchanges1),
	Exchanges3 = dict:store([<<"test2">>, <<"test1">>], <<"test2">>, Exchanges2),
	Exchanges4 = dict:store([<<"test3">>, <<"test2">>, <<"test1">>], <<"test3">>, Exchanges3),

	Exchanges5 = dict:store([<<"core">>], <<"core-service">>, Exchanges4),

	%%huotianjun tsung report
	Exchanges6 = dict:store([<<"log">>], <<"report">>, Exchanges5), 
	Exchanges7 = dict:store([<<"stock">>], <<"stock">>, Exchanges6),
	Exchanges8 = dict:store([<<"maker">>], <<"maker">>, Exchanges7),

	HostExchanges1 = dict:store(<<"localhost">>, Exchanges8, HostExchanges), 
	HostExchanges2 = dict:store(<<"101.200.162.101">>, Exchanges8, HostExchanges1),

	Exchanges108 = dict:store([<<"/">>], <<"stock">>, dict:new()),
	HostExchanges3 = dict:store(<<"106.187.44.101">>, Exchanges108, HostExchanges2),

	set_ranch_opts_exchanges(HostExchanges3).

%%huotianjun 把Exchanges设置到ranch core opts中
set_ranch_opts_routingkeys(HostExchanges) ->
	Opts = ranch_server:get_protocol_options(http),
	Opts1 = Opts#{rpc_exchanges => HostExchanges},
	ok = ranch_server:set_protocol_options(http, Opts1).

declare_exchange(ExchangeName) ->
	{ok, Pid} =  webmqx_rpc_channel_manager:get_rpc_channel_pid(), 
	webmqx_rpc_channel:declare_exchange(Pid, ExchangeName).

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
