-module(webmqx_binding_event_handler).

-behaviour(gen_event).

-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).

%%%
%%% Callbacks of rabbit_event
%%%

init([]) ->
  {ok, []}.

handle_event({event, webmqx_binding_add, {WordsOfPath, _X, _D, _Args}, _, _}, State) ->
	%% Flush the routing ring.
	webmqx_gm:flush_routing_ring(WordsOfPath),
	error_logger:info_msg("webmqx_binding_event_handler : flush ~p~n", [WordsOfPath]),

	%% Try starting a broker to handle consistent requests of the http path.
	Path = webmqx_util:words_to_path(WordsOfPath),
	webmqx_consistent_req_sup:start_child(Path),
	{ok, State};

handle_event({event, webmqx_binding_remove, {WordsOfPath, _X, _D, _Args}, _, _}, State) ->
	%% Flush the ets of routing table.
	webmqx_gm:flush_routing_ring(WordsOfPath),
	error_logger:info_msg("webmqx_binding_event_handler : flush ~p~n", [WordsOfPath]),

	%% Try to stop the broker.
	Path = webmqx_util:words_to_path(WordsOfPath),
	webmqx_consistent_req_sup:delete_child(Path),
	error_logger:info_msg("delete child : ~p~n", [Path]),
	{ok, State};

handle_event(_Event, State) ->
	{ok, State}.

handle_call(_Request, State) ->
	{ok, State}.

handle_info(_Info, State) ->
	{ok, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.
