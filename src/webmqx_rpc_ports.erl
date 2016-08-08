-module(webmqx_rpc_ports).

-export([init/0, search_port/3, table_definitions/0]).
-export([dirty_read_port/1, remove_port/1, get_path_port/1, add_path_port/2, update_path_port/3, remove_path_port/2]).

%%huotianjun path是{Host, Path}
-record(rpc_path_port, {path, port}).

-define(TABLE, rpc_path_port).

%%huotianjun 定义rpc_ports表结构
-define(TABLE_DEFINE, {?TABLE, [{record_name, rpc_path_port},
								{disc_copies, [node()]},
								{attributes, record_info(fields, rpc_path_port)}]}).

%%huotianjun 把这个加入了table描述的attributes里面了？
-define(TABLE_MATCH, {match, #rpc_path_port { _ = '_' }}).

init() ->
	%%huotianjun rpc ports初始化时由这里加进去
	%%huotianjun 运行中可触发变动，通过ranch_server:set_protocol_opts，它可以自动通知内核变动！！！
	HostPorts = dict:new(),
	Ports = dict:new(),

	%%huotianjun 注意：在ports的数据库中，key是<<"/test1/test2/test3">>，取出来后，在应用dict中的key转换为：[<<"test3">>, <<"test2">>, <<"test1">>]。根是特殊的：[<<"/">>]
	Ports1 = dict:store([<<"/">>], <<"stock">>, Ports),

	Ports2 = dict:store([<<"test1">>], <<"test1">>, Ports1),
	Ports3 = dict:store([<<"test2">>, <<"test1">>], <<"test2">>, Ports2),
	Ports4 = dict:store([<<"test3">>, <<"test2">>, <<"test1">>], <<"test3">>, Ports3),

	Ports5 = dict:store([<<"core">>], <<"core-service">>, Ports4),

	%%huotianjun tsung report
	Ports6 = dict:store([<<"log">>], <<"report">>, Ports5), 
	Ports7 = dict:store([<<"stock">>], <<"stock">>, Ports6),
	Ports8 = dict:store([<<"maker">>], <<"maker">>, Ports7),

	HostPorts1 = dict:store(<<"localhost">>, Ports8, HostPorts), 
	HostPorts2 = dict:store(<<"101.200.162.101">>, Ports8, HostPorts1),

	Ports108 = dict:store([<<"/">>], <<"stock">>, dict:new()),
	HostPorts3 = dict:store(<<"106.187.44.101">>, Ports108, HostPorts2),

	declare_port(<<"test1">>),
	declare_port(<<"test2">>),
	declare_port(<<"test3">>),
	declare_port(<<"report">>),
	declare_port(<<"stock">>),
	declare_port(<<"maker">>),

	set_ranch_opts_ports(HostPorts3).


%%huotianjun 把Ports设置到ranch core opts中
set_ranch_opts_ports(HostPorts) ->
	Opts = ranch_server:get_protocol_options(http),
	Opts1 = Opts#{rpc_ports => HostPorts},
	ok = ranch_server:set_protocol_options(http, Opts1).

declare_port(PortName) ->
	{ok, Pid} =  webmqx_rpc_clients_manager:get_rpc_pid(), 
	webmqx_rpc_client:declare_port(Pid, PortName).

%%huotianjun 注意：ports从数据库中取出来，key是split path的lists，就设成倒序的！！ 设置到HostPorts中
%%huotianjun HostPorts放置到ranch core Opts map中
%%
search_port(Host, Path, HostPorts) when is_binary(Path) ->
	SplitPath = webmqx_util:split_path(Path),
	search_port(Host, SplitPath, HostPorts);

search_port(Host, SplitPath, HostPorts)  ->
	case dict:find(Host, HostPorts) of 
		{ok, Ports} -> search_port1(SplitPath, Ports);
		_ -> undefined 
	end.

search_port1([], Ports) ->
	case dict:find([<<"/">>], Ports) of 
		{ok, Port} ->
			{ok, Port};
		_ ->
			undefined
	end;

search_port1(SplitPath = [_|Rest] , Ports) ->
	case dict:find(SplitPath, Ports) of
		{ok, Port} ->
			{ok, Port};
		_ ->
			search_port1(Rest, Ports) 
	end.

%%huotianjun mnesia
%%
%%huotianjun 定义rpc_ports的表结构
table_definitions() ->
    {Name, Attributes} = ?TABLE_DEFINE,
    [{Name, [?TABLE_MATCH | Attributes]}].

%%huotianjun Path {Host，[PathFirst, PathSecond, ...]}
dirty_read_port({Host, Path}) when is_list(Path), is_binary(Host)->
    case mnesia:dirty_read(?TABLE, {Host, Path}) of
        []      -> {error, not_found};
        [Port] -> {ok, Port}
    end.

%%huotianjun read、write只能在transaction里面用，不能单独用
read_port({Host, Path}) when is_list(Path), is_binary(Host)->
    case mnesia:read({?TABLE, {Host, Path}}) of
        []      -> {error, not_found};
        [PathPort] -> {ok, PathPort};
		_ -> {error, more_records}
    end.

write_port({Host, Path}, Port) when is_binary(Host), is_list(Path), is_binary(Port)-> 
	PathPort = #rpc_path_port{ path = {Host, Path}, port = Port},
	mnesia:write(?TABLE, PathPort, write),
	ok.

remove_port({Host, Path}) ->
	mnesia:delete({?TABLE, {Host, Path}}),
	ok.

get_path_port({Host, Path}) when is_list(Path), is_binary(Host) ->
    rabbit_misc:execute_mnesia_transaction(
      fun () ->
              case read_port({Host, Path}) of
					{ok, PathPort} ->
						{ok, PathPort};
					{error, not_found} ->
						{error, not_found};
					{error, Err} ->
						{error, Err}
              end
      end
	 ).

add_path_port({Host, Path}, Port) when is_list(Path), is_binary(Host), is_binary(Port) ->
    rabbit_misc:execute_mnesia_transaction(
      fun () ->
              case read_port({Host, Path}) of
					{ok, _PathPort} ->
						{error, already};
					{error, not_found} ->
						write_port({Host, Path}, Port);
					{error, Err} ->
						{error, Err}
              end
      end
	 ).

update_path_port({Host, Path}, PortOld, PortNew) when is_list(Path), is_binary(Host), is_binary(PortOld), is_binary(PortNew) ->
    rabbit_misc:execute_mnesia_transaction(
      fun () ->
              case read_port({Host, Path}) of
					{ok, #rpc_path_port{port = PortOld}} ->
						remove_port({Host, Path}),
						write_port({Host, Path}, PortNew);
					{ok, _PathPort} ->
						{error, no_this_record};					  
					{error, not_found} ->
						{error, not_found};
					{error, Err} ->
						{error, Err}
              end
      end
	).

remove_path_port({Host, Path}, Port) when is_list(Path), is_binary(Host), is_binary(Port) ->
    rabbit_misc:execute_mnesia_transaction(
      fun () ->
              case read_port({Host, Path}) of
					{ok, #rpc_path_port{path = {Host, Path}, port = Port}} ->
						remove_port({Host, Path});
					{ok, _}  ->
						{error,  no_this_record};
					{error, not_found} ->
						{error, not_found};
					{error, Err} ->
						{error, Err}
              end
      end
	).
