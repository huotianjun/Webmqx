%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_exchange_type_webmqx).

-include_lib("rabbit_common/include/rabbit.hrl").
-include("webmqx.hrl").

-behaviour(rabbit_exchange_type).

-export([description/0, serialise_events/0, route/2]).
-export([validate/1, validate_binding/2,
         create/2, delete/3, policy_changed/2, add_binding/3,
         remove_bindings/3, assert_args_equivalence/2]).
-export([fetch_routing_queues/3, fetch_bindings_info/3]).
-export([info/1, info/2]).

-rabbit_boot_step({?MODULE,
                   [{description, "exchange type webmqx"},
                    {mfa,         {rabbit_registry, register,
                                   [exchange, ?EXCHANGE_WEBMQX_TYPE, ?MODULE]}},
                    {requires,    rabbit_registry},
                    {enables,     kernel_ready}]}).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-type(match_result() :: [rabbit_types:binding_destination()]).
-spec(fetch_routing_queues/3 :: (binary()), binary(), [string()]) -> match_result()).
-spec(fetch_bindings_info/3 :: (binary()), binary(), [string()]) -> [any()].

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported functions
%%%

%% Called by webmqx_exchange_routes 
fetch_routing_queues(VHost, Exchange, WordsOfPath) when is_list(WordsOfPath) ->
    mnesia:async_dirty(fun trie_match/2, [#resource{virtual_host = VHost, kind = exchange, name = Exchange}, WordsOfPath]).

fetch_bindings_info(VHost, Exchange, WordsOfPath) when is_list(WordsOfPath) ->
    mnesia:async_dirty(fun trie_match_info/2, [#resource{virtual_host = VHost, kind = exchange, name = Exchange}, WordsOfPath]).

%%%
%%% Callbacks of rabbit_exchange
%%%

info(_X) -> [].
info(_X, _) -> [].

description() ->
    [{description, <<"AMQP webmqx exchange, as per the AMQP specification">>}].

serialise_events() -> false.

route(_X, #delivery{message = #basic_message{routing_keys = Routes}}) ->
	lists:append([begin
						webmqx_exchange_routes:route(RKey)			
				end || RKey <- Routes]).

validate(_X) -> ok.
validate_binding(_X, _B) -> ok.
create(_Tx, _X) -> ok.

delete(transaction, #exchange{name = X}, _Bs) ->
    trie_remove_all_nodes(X),
    trie_remove_all_edges(X),
    trie_remove_all_bindings(X),
    ok;
delete(none, _Exchange, _Bs) ->
    ok.

policy_changed(_X1, _X2) -> ok.

add_binding(transaction, _Exchange, Binding) ->
    internal_add_binding(Binding);
add_binding(none, _Exchange, Binding) ->
	%% Called after add_binding transaction completed, for update webmqx_exchange_routes of all nodes. 
	#binding{source = X, key = K, destination = D, args = Args} = Binding,
    rabbit_event:notify(binding_add, {webmqx_util:path_to_words(K), X, D, Args}),  
    ok.

remove_bindings(transaction, _X, Bs) ->
    %% See rabbit_binding:lock_route_tables for the rationale for
    %% taking table locks.
    case Bs of
        [_] -> ok;
        _   -> [mnesia:lock({table, T}, write) ||
                   T <- [rabbit_topic_trie_node,
                         rabbit_topic_trie_edge,
                         rabbit_topic_trie_binding]]
    end,
    [case follow_down_get_path(X, webmqx_util:path_to_words(K)) of
         {ok, Path = [{FinalNode, _} | _]} ->
             trie_remove_binding(X, FinalNode, D, Args),

             remove_path_if_empty(X, Path);
         {error, _Node, _RestW} ->
             %% We're trying to remove a binding that no longer exists.
             %% That's unexpected, but shouldn't be a problem.
             ok
     end ||  #binding{source = X, key = K, destination = D, args = Args} <- Bs],
    ok;
remove_bindings(none, _X, Bs) ->
	%% Called after remove_binding transaction completed, for update webmqx_exchange_routes of all nodes. 
    [rabbit_event:notify(binding_remove, {webmqx_util:path_to_words(K), X, D, Args})  
		||  #binding{source = X, key = K, destination = D, args = Args} <- Bs],
    ok.

assert_args_equivalence(X, Args) ->
    rabbit_exchange:assert_args_equivalence(X, Args).

internal_add_binding(#binding{source = X, key = K, destination = D,
                              args = Args}) ->
    FinalNode = follow_down_create(X, webmqx_util:path_to_words(K)),
    trie_add_binding(X, FinalNode, D, Args),
    ok.

trie_match(X, Words) ->
    Node = trie_match(X, root, Words),
	trie_bindings(X, Node).

trie_match_info(X, Words) ->
	Node = trie_match(X, root, Words),
	trie_bindings_info(X, Node).

trie_match(_X, Node, []) -> Node;
trie_match(X, Node, [W | RestW]) ->
	trie_match_part(X, Node, W, fun trie_match/3, RestW).

trie_match_part(X, Node, Search, MatchFun, RestW) ->
    case trie_child(X, Node, Search) of
        {ok, NextNode} -> 
			MatchFun(X, NextNode, RestW);
        error          -> []
    end.

follow_down_create(X, Words) ->
    case follow_down_last_node(X, Words) of
        {ok, FinalNode}      -> FinalNode;
        {error, Node, RestW} -> lists:foldl(
                                  fun (W, CurNode) ->
                                          NewNode = new_node_id(),
                                          trie_add_edge(X, CurNode, NewNode, W),
                                          NewNode
                                  end, Node, RestW)
    end.

follow_down_last_node(X, Words) ->
    follow_down(X, fun (_, Node, _) -> Node end, root, Words).

follow_down_get_path(X, Words) ->
    follow_down(X, fun (W, Node, PathAcc) -> [{Node, W} | PathAcc] end,
                [{root, none}], Words).

follow_down(X, AccFun, Acc0, Words) ->
    follow_down(X, root, AccFun, Acc0, Words).

follow_down(_X, _CurNode, _AccFun, Acc, []) ->
    {ok, Acc};
follow_down(X, CurNode, AccFun, Acc, Words = [W | RestW]) ->
    case trie_child(X, CurNode, W) of
        {ok, NextNode} -> follow_down(X, NextNode, AccFun,
                                      AccFun(W, NextNode, Acc), RestW);
        error          -> {error, Acc, Words}
    end.

remove_path_if_empty(_, [{root, none}]) ->
    ok;
remove_path_if_empty(X, [{Node, W} | [{Parent, _} | _] = RestPath]) ->
    case mnesia:read(rabbit_topic_trie_node,
                     #trie_node{exchange_name = X, node_id = Node}, write) of
        [] -> trie_remove_edge(X, Parent, Node, W),
              remove_path_if_empty(X, RestPath);
        _  -> ok
    end.

trie_child(X, Node, Word) ->
    case mnesia:read({rabbit_topic_trie_edge,
                      #trie_edge{exchange_name = X,
                                 node_id       = Node,
                                 word          = Word}}) of
        [#topic_trie_edge{node_id = NextNode}] -> {ok, NextNode};
        []                                     -> error
    end.

trie_bindings(X, Node) ->
    MatchHead = #topic_trie_binding{
      trie_binding = #trie_binding{exchange_name = X,
                                   node_id       = Node,
                                   destination   = '$1',
                                   arguments     = '_'}},
    mnesia:select(rabbit_topic_trie_binding, [{MatchHead, [], ['$1']}]).

trie_bindings_info(X, Node) ->
    MatchHead = #topic_trie_binding{
      trie_binding = #trie_binding{exchange_name = X,
                                   node_id       = Node,
                                   destination   = '_',
                                   arguments     = '$1'}},
    mnesia:select(rabbit_topic_trie_binding, [{MatchHead, [], ['$1']}]).

trie_update_node_counts(X, Node, Field, Delta) ->
    E = case mnesia:read(rabbit_topic_trie_node,
                         #trie_node{exchange_name = X,
                                    node_id       = Node}, write) of
            []   -> #topic_trie_node{trie_node = #trie_node{
                                       exchange_name = X,
                                       node_id       = Node},
                                     edge_count    = 0,
                                     binding_count = 0};
            [E0] -> E0
        end,
    case setelement(Field, E, element(Field, E) + Delta) of
        #topic_trie_node{edge_count = 0, binding_count = 0} ->
            ok = mnesia:delete_object(rabbit_topic_trie_node, E, write);
        EN ->
            ok = mnesia:write(rabbit_topic_trie_node, EN, write)
    end.

trie_add_edge(X, FromNode, ToNode, W) ->
    trie_update_node_counts(X, FromNode, #topic_trie_node.edge_count, +1),
    trie_edge_op(X, FromNode, ToNode, W, fun mnesia:write/3).

trie_remove_edge(X, FromNode, ToNode, W) ->
    trie_update_node_counts(X, FromNode, #topic_trie_node.edge_count, -1),
    trie_edge_op(X, FromNode, ToNode, W, fun mnesia:delete_object/3).

trie_edge_op(X, FromNode, ToNode, W, Op) ->
    ok = Op(rabbit_topic_trie_edge,
            #topic_trie_edge{trie_edge = #trie_edge{exchange_name = X,
                                                    node_id       = FromNode,
                                                    word          = W},
                             node_id   = ToNode},
            write).

trie_add_binding(X, Node, D, Args) ->
    trie_update_node_counts(X, Node, #topic_trie_node.binding_count, +1),
    trie_binding_op(X, Node, D, Args, fun mnesia:write/3).

trie_remove_binding(X, Node, D, Args) ->
    trie_update_node_counts(X, Node, #topic_trie_node.binding_count, -1),
    trie_binding_op(X, Node, D, Args, fun mnesia:delete_object/3).

trie_binding_op(X, Node, D, Args, Op) ->
    ok = Op(rabbit_topic_trie_binding,
            #topic_trie_binding{
              trie_binding = #trie_binding{exchange_name = X,
                                           node_id       = Node,
                                           destination   = D,
                                           arguments     = Args}},
            write).

trie_remove_all_nodes(X) ->
    remove_all(rabbit_topic_trie_node,
               #topic_trie_node{trie_node = #trie_node{exchange_name = X,
                                                       _             = '_'},
                                _         = '_'}).

trie_remove_all_edges(X) ->
    remove_all(rabbit_topic_trie_edge,
               #topic_trie_edge{trie_edge = #trie_edge{exchange_name = X,
                                                       _             = '_'},
                                _         = '_'}).

trie_remove_all_bindings(X) ->
    remove_all(rabbit_topic_trie_binding,
               #topic_trie_binding{
                 trie_binding = #trie_binding{exchange_name = X, _ = '_'},
                 _            = '_'}).

remove_all(Table, Pattern) ->
    lists:foreach(fun (R) -> mnesia:delete_object(Table, R, write) end,
                  mnesia:match_object(Table, Pattern, write)).

new_node_id() ->
    rabbit_guid:gen().
