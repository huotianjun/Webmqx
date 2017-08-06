-module(webmqx_ws_handler).

-export([init/2]).
-export([websocket_init/1]).
-export([websocket_handle/2]).
-export([websocket_info/2]).

init(Req = #{host := Host, method := Method, path := Path, qs := Qs}, Opts) ->
    error_logger:info_msg("init : ~p ~p", [Req, Opts]),
	{cowboy_websocket, Req, Opts#{host => Host, method => Method, path => Path, qs => Qs}}.

websocket_init(State) ->
    error_logger:info_msg("websocket_init ~p", [State]),
	{ok, State}.

websocket_handle({text, Msg}, State = #{host := Host, 
                                        method := _Method, 
                                        path := Path, 
                                        qs := _Qs, 
                                        rpc_workers_num := WorkersNum}) ->

    error_logger:info_msg("request : ~p ~n", [Msg]),

    try
        case webmqx_rpc_worker_manager:get_a_worker(WorkersNum) of
            undefined -> 
                error_logger:info_msg("get a worker error"),
                {stop, State};
            {ok, RpcWorkerPid} ->
                webmqx_rpc_worker:rpc(async, RpcWorkerPid, Host, Path, Msg)
        end
    catch
        _Error:_Reason ->
            {stop, State} 
    end,

    {ok, State};
    
websocket_handle(Data, State) ->
    error_logger:info_msg("handle other ws-msg: ~p ~p", [Data, State]),
	{ok, State}.

websocket_info({timeout, _Ref, Msg}, State) ->
	{reply, {text, Msg}, State};
websocket_info({error, Msg}, State) ->
    error_logger:info_msg("ws response error: ~p ~p", [Msg, State]),
    {stop, State};
websocket_info({'$gen_cast', {response, Msg}}, State) ->
    error_logger:info_msg("ws response : ~p ~p", [Msg, State]),
	{reply, {text, Msg}, State};
websocket_info({'$gen_cast', {error, Msg}}, State) ->
    error_logger:info_msg("ws response error: ~p ~p", [Msg, State]),
	{ok, State};
websocket_info(Data, State) ->
    error_logger:info_msg("ws response unknown : ~p", [Data]),
    {ok, State}.


