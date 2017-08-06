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
    {ok, State};

handle_event({event, webmqx_binding_remove, {WordsOfPath, _X, _D, _Args}, _, _}, State) ->
    %% Flush the ets of routing table.
    webmqx_gm:flush_routing_ring(WordsOfPath),

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
