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

-module(webmqx_util).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("webmqx.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

env(Key) ->
    case application:get_env(?APP, Key) of
        {ok, Val} -> Val;
        undefined -> undefined
    end.

words_to_path(Words) ->
	words_to_path(Words, []).

words_to_path([], Acc) -> list_to_binary(lists:reverse(Acc));
words_to_path([Word|Rest], Acc) ->
	words_to_path(Rest, [Word | ["/" | Acc]]).


split_path_key(Key) ->
    split_path_key(Key, [], []).

split_path_key(<<>>, [], []) ->
    [];
split_path_key(<<>>, [], RevResAcc) ->
    lists:reverse(RevResAcc);
split_path_key(<<>>, RevWordAcc, RevResAcc) ->
    lists:reverse([lists:reverse(RevWordAcc) | RevResAcc]);
%%huotianjun split by '/'
split_path_key(<<$/, Rest/binary>>, [], RevResAcc) ->
    split_path_key(Rest, [], RevResAcc);
split_path_key(<<$/, Rest/binary>>, RevWordAcc, RevResAcc) ->
    split_path_key(Rest, [], [lists:reverse(RevWordAcc) | RevResAcc]);
split_path_key(<<C:8, Rest/binary>>, RevWordAcc, RevResAcc) ->
    split_path_key(Rest, [C | RevWordAcc], RevResAcc).
