-module(webmqx_consistent_req_sup).
-behaviour(supervisor2).

-export([start_link/0, init/1, start_child/1, 
         delete_child/1]).

-define(ENCODING, utf8).

-ifdef(use_specs).
-spec(start_child/1 :: (binary()) -> supervisor2:startchild_ret()).
-spec(start_child/2 :: (term(), binary()) -> supervisor2:startchild_ret()).
-endif.

start_link() ->
	supervisor2:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Path) when is_binary(Path) ->
	case start_child1(Path) of
		{ok, Pid}                       -> Pid;
		{error, {already_started, Pid}} -> Pid
	end.

start_child1(Path) ->
	supervisor2:start_child(?MODULE,
		%%huotianjun unique id of req's path.
		{binary_to_atom(Path, ?ENCODING),
		{webmqx_consistent_req_broker, start_link, [Path]},
		permanent, 60, worker, [webmqx_consistent_req_broker]}).

delete_child(Path) ->
	case webmqx_exchange_routing:queues_count(Path) of
		0 ->
			Id = binary_to_atom(Path, ?ENCODING),
			ok = supervisor2:terminate_child(?MODULE, Id),
			ok = supervisor2:delete_child(?MODULE, Id);
		_ -> ok
	end.

init([]) ->
  {ok, {{one_for_one, 5, 10}, []}}.

