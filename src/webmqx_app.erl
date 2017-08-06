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

    %% Manage ets table of searching table for webmqx routing.
    webmqx_gm:start(),

    %% RPC workers start.
    webmqx_rpc_worker_manager:start(),
    webmqx_sup:start_supervisor_child(webmqx_rpc_worker_sup),

    %% Cowboy start
    RpcWorkersNum = webmqx_util:env_rpc_workers_num(),
    Dispatch = cowboy_router:compile([
        {'_', [
            {'_', webmqx_http_handler, #{rpc_workers_num => RpcWorkersNum}}
        ]}
    ]),
    Port = webmqx_util:env_port(),
    {ok, _Cowboy} = cowboy:start_clear(http, 100, [{port, Port}], 
        #{env => #{dispatch => Dispatch}} 
    ),

    %% Add event handler for binding_add or binding_remove events.
    EventPid =
    case rabbit_event:start_link() of
        {ok, Pid}                       -> Pid;
        {error, {already_started, Pid}} -> Pid
    end,
    gen_event:add_handler(EventPid, webmqx_binding_event_handler, []),

    %% For test.
    webmqx_service_internal:start(),

    Result.

stop(_State) ->
    ok.
