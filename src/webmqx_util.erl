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
%% The Original Code is Webmqx.
%%
%% Copyright Webmqx.  All rights reserved.
%%

-module(webmqx_util).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("webmqx.hrl").

-compile(export_all).

env(Key) ->
    case application:get_env(?APP, Key) of
        {ok, Val} -> Val;
        undefined -> undefined
    end.

words_to_path(Words) when is_list(Words)->
	words_to_path(Words, []).

words_to_path(["/"], []) -> <<"/">>;
words_to_path([], []) -> <<"/">>;
words_to_path([], Acc) -> list_to_binary(lists:reverse(Acc));
words_to_path([Word|Rest], Acc) ->
	words_to_path(Rest, [Word | ["/" | Acc]]).

path_to_words(Path) when is_binary(Path)->
    path_to_words(Path, [], []).

path_to_words(<<$/>>, [], []) ->
	["/"];
path_to_words(<<>>, [], []) ->
    ["/"];
path_to_words(<<>>, [], Acc) ->
    lists:reverse(Acc);
path_to_words(<<>>, Word, Acc) ->
    lists:reverse([lists:reverse(Word) | Acc]);
%%huotianjun split by '/'
path_to_words(<<$/, Rest/binary>>, [], Acc) ->
    path_to_words(Rest, [], Acc);
path_to_words(<<$/, Rest/binary>>, Word, Acc) ->
    path_to_words(Rest, [], [lists:reverse(Word) | Acc]);
path_to_words(<<C:8, Rest/binary>>, Word, Acc) ->
    path_to_words(Rest, [C | Word], Acc).
