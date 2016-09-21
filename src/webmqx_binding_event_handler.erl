-module(webmqx_binding_event_handler).

-behaviour(gen_event).

-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).

%%%
%%% Callbacks of rabbit_event
%%%

init([]) ->
  {ok, []}.

handle_event({event, binding_add, Info, _, _}, State) ->
	error_logger:info_msg("event : ~p~n", [Info]),
	{ok, State};

handle_event({event, binding_add, {PathSplited, _X, _D, _Args}, _, _}, State) ->
	error_logger:info_msg("binding_add ~p~n", [PathSplited]),
	webmqx_exchange_routing:flush_routing_queues(PathSplited),
	Path = webmqx_util:words_to_path(PathSplited),
	webmqx_consistent_req_sup:start_child(Path),
	{ok, State};

handle_event({event, binding_remove, Info, _, _}, State) ->
	error_logger:info_msg("event : ~p~n", [Info]),
	{ok, State};

handle_event({event, binding_remove, {PathSplited, _X, _D, _Args}, _, _}, State) ->
	error_logger:info_msg("binding_remove ~p~n", [PathSplited]),
	webmqx_exchange_routing:flush_routing_queues(PathSplited),
	Path = webmqx_util:words_to_path(PathSplited),
	webmqx_consistent_req_sup:delete_child(Path),
	{ok, State};

handle_event(Event, State) ->
	error_logger:info_msg("unknown event : ~p ~n", [Event]),
	{ok, State}.

handle_call(_Request, State) ->
	{ok, State}.

handle_info(_Info, State) ->
	{ok, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.
