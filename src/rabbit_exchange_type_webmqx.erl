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

-define(WEBMQX_EXCHANGE, <<"webmqx">>).

-behaviour(rabbit_exchange_type).

-export([description/0, serialise_events/0, route/2]).
-export([validate/1, validate_binding/2,
         create/2, delete/3, policy_changed/2, add_binding/3,
         remove_bindings/3, assert_args_equivalence/2]).
-export([fetch_routing_queues/1]).
-export([split_topic_key/1]).
-export([info/1, info/2]).

-rabbit_boot_step({?MODULE,
                   [{description, "exchange type webmqx"},
                    {mfa,         {rabbit_registry, register,
                                   [exchange, ?WEBMQX_EXCHANGE, ?MODULE]}},
                    {requires,    rabbit_registry},
                    {enables,     kernel_ready}]}).

%%----------------------------------------------------------------------------

info(_X) -> [].
info(_X, _) -> [].

description() ->
    [{description, <<"AMQP webmqx exchange, as per the AMQP specification">>}].

serialise_events() -> false.

%% NB: This may return duplicate results in some situations (that's ok)
%% huotianjun 这个exchange只是借用了binding及其数据库表，不用exchange的route，在应用中直接match Queues。
route(_X, _D} -> ok.

%%huotianjun 提取Routing最新的Queues
fetch_routing_queues(RoutingWords) when is_list(RoutingWords) ->
    mnesia:async_dirty(fun trie_match/2, [?WEBMQX_EXCHANGE, RoutingWords]).

validate(_X) -> ok.

validate_binding(_X, _B) -> ok.

create(_Tx, _X) -> ok.

delete(transaction, #exchange{name = X}, _Bs) ->
	%%huotianjun 分三个层面描述binding及其节点信息
    trie_remove_all_nodes(X),
    trie_remove_all_edges(X),
    trie_remove_all_bindings(X),
    ok;
delete(none, _Exchange, _Bs) ->
    ok.

policy_changed(_X1, _X2) -> ok.

add_binding(transaction, _Exchange, Binding) ->
    internal_add_binding(Binding);
add_binding(none, _Exchange, _Binding) ->
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
    [case follow_down_get_path(X, TopicSplited = split_topic_key(K)) of
         {ok, Path = [{FinalNode, _} | _]} ->
             trie_remove_binding(X, FinalNode, D, Args),

			 %%huotianjun 发出gm广播消息flush
			 webmqx_rpc_routing_queues:flush_routing_queues(TopicSplited),

			 %%huotianjun 没有后续节点，层层网上删
             remove_path_if_empty(X, Path);
         {error, _Node, _RestW} ->
             %% We're trying to remove a binding that no longer exists.
             %% That's unexpected, but shouldn't be a problem.
             ok
     end ||  #binding{source = X, key = K, destination = D, args = Args} <- Bs],
    ok;
remove_bindings(none, _X, _Bs) ->
    ok.

assert_args_equivalence(X, Args) ->
    rabbit_exchange:assert_args_equivalence(X, Args).

%%----------------------------------------------------------------------------

internal_add_binding(#binding{source = X, key = K, destination = D,
                              args = Args}) ->
    TopicSplited = split_topic_key(K),
    FinalNode = follow_down_create(X, TopicSplited),
    trie_add_binding(X, FinalNode, D, Args),

	%%huotianjun 这里要发一个gm广播消息，
	webmqx_rpc_routing_queues:flush_routing_queues(TopicSplited),
    ok.

%%huotianjun 严格匹配，节点数量必须一样
trie_match(X, Words) ->
    trie_match(X, root, Words).

%%huotianjun 最终取到的是bindings的destination
trie_match(X, Node, []) ->
	trie_bindings(X, Node);
trie_match(X, Node, [W | RestW])  ->
	trie_match_part(X, Node, W, RestW).

trie_match_part(X, Node, Search, RestW) ->
    case trie_child(X, Node, Search) of
        {ok, NextNode} -> trie_match(X, NextNode, RestW);
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

%%huotianjun 一个Node的binding可能有多个
%%huotianjun 最终取到的是destination
trie_bindings(X, Node) ->
    MatchHead = #topic_trie_binding{
      trie_binding = #trie_binding{exchange_name = X,
                                   node_id       = Node,
                                   destination   = '$1',
                                   arguments     = '_'}},
	%%huotianjun select 匹配map、条件、输出
    mnesia:select(rabbit_topic_trie_binding, [{MatchHead, [], ['$1']}]).

trie_update_node_counts(X, Node, Field, Delta) ->
    E = case mnesia:read(rabbit_topic_trie_node,
                         #trie_node{exchange_name = X,
                                    node_id       = Node}, write) of
			%%huotianjun 初始化
            []   -> #topic_trie_node{trie_node = #trie_node{
                                       exchange_name = X,
                                       node_id       = Node},
                                     edge_count    = 0,
                                     binding_count = 0};
            [E0] -> E0
        end,
	%%huotianjun record的update
    case setelement(Field, E, element(Field, E) + Delta) of
        #topic_trie_node{edge_count = 0, binding_count = 0} ->
			%%huotianjun 空了就删除
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

%%huotianjun 抽象一个对节点的操作
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

split_topic_key(Key) ->
    split_topic_key(Key, [], []).

split_topic_key(<<>>, [], []) ->
    [];
split_topic_key(<<>>, RevWordAcc, RevResAcc) ->
    lists:reverse([lists:reverse(RevWordAcc) | RevResAcc]);
%%huotianjun split by '/'
split_topic_key(<<$/, Rest/binary>>, RevWordAcc, RevResAcc) ->
    split_topic_key(Rest, [], [lists:reverse(RevWordAcc) | RevResAcc]);
split_topic_key(<<C:8, Rest/binary>>, RevWordAcc, RevResAcc) ->
    split_topic_key(Rest, [C | RevWordAcc], RevResAcc).
