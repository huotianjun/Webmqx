-module(webmqx_gm).

-include_lib("rabbit/include/gm_specs.hrl").
-include("webmqx.hrl").

-behaviour(gen_server2).

%% For update all nodes.
-behaviour(gm).

%% APIs.
-export([start/0]).
-export([start_link/0]).
-export([flush_routing_ring/1]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% GM callbacks 
-export([joined/2, members_changed/3, handle_msg/3, handle_terminate/2]).

-define(TAB, ?MODULE).

-record(state, {
				gm = undefined
				}). 

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(start_link/0 :: () -> rabbit_types:ok_pid_or_error().
-spec(start/0 :: () -> rabbit_types:ok_or_error(any())).

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported functions
%%%

start_link() ->
	gen_server2:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
    ensure_started().

%% Called from webmqx_binding_event_handler.
flush_routing_ring(WordsOfPath) ->
	gen_server2:cast(?MODULE, {flush_routing_ring, WordsOfPath}).

%%%
%%% Callbacks of gen_server
%%%

init([]) ->
	{ok, GM} = gm:start_link(?MODULE, ?MODULE, [self()],
							 fun rabbit_misc:execute_mnesia_transaction/1),
	MRef = erlang:monitor(process, GM),

	receive
		{joined, GM}            -> error_logger:info_msg("webmqx_gm ~p is joined~n", [GM]),
									erlang:demonitor(MRef, [flush]),
									ok;
		{'DOWN', MRef, _, _, _} -> error_logger:info_msg("start link gm DOWN!"),		
									ok 
	end,
	error_logger:info_msg("webmqx_gm is started"),

	{ok, #state{gm = GM}}.

handle_call(_Request, _From, State) ->
	{reply, ignore, State}.

handle_cast({flush_routing_ring, WordsOfPath}, State = #state{gm = GM}) ->
	gm:broadcast(GM, {flush_routing_ring, WordsOfPath}),
	{noreply, State};

%% All nodes update their routing rings.
handle_cast({gm, {flush_routing_ring, WordsOfPath}}, State) ->
	webmqx_rpc_worker_sup:flush_routing_ring(WordsOfPath),
	{noreply, State};

handle_cast(_Request, State) ->
	{noreply, State}.

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

ensure_started() ->
    case whereis(?MODULE) of
        undefined ->
			webmqx_sup:start_restartable_child(?MODULE);
        _Pid ->
            ok
    end.

%%%
%%% Callbacks of GM
%%%

joined([SPid], _Members) -> 
	SPid ! {joined, self()}, ok.

members_changed([_SPid], _Births, _) ->
    ok.

handle_msg([SPid], _From, Msg) ->
    ok = gen_server2:cast(SPid, {gm, Msg}).

handle_terminate([_SPid], Reason) ->
	error_logger:info_msg("handle_terminate Reason : ~p ~n", [Reason]),
    ok.
