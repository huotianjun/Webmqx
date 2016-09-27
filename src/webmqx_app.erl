-module(webmqx_app).
-behaviour(application).

-include_lib("rabbit_common/include/rabbit.hrl").

-export([start/2]).
-export([stop/1]).

%%%
%%% Callbacks of application
%%%

start(_Type, _Args) ->
	Result = webmqx_sup:start_link(),

	webmqx_exchange_routing:start(),

	webmqx_rpc_worker_manager:start(),
	webmqx_sup:start_supervisor_child(webmqx_rpc_worker_sup),
	webmqx_sup:start_supervisor_child(webmqx_consistent_req_sup),

	webmqx_service_internal:start(),

	RpcWorkersNum = webmqx_util:env_rpc_workers_num(),

	Dispatch = cowboy_router:compile([
		{'_', [
			{'_', webmqx_http_handler, #{rpc_workers_num => RpcWorkersNum}}
		]}
	]),

	{ok, _Cowboy} = cowboy:start_clear(http, 100, [{port, 8080}], 
		#{env => #{dispatch => Dispatch}} 
	),

	EventPid =
	case rabbit_event:start_link() of
		{ok, Pid}                       -> Pid;
		{error, {already_started, Pid}} -> Pid
	end,
	gen_event:add_handler(EventPid, webmqx_binding_event_handler, []),

	Result.

stop(_State) ->
	ok.
