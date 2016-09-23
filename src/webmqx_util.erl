-module(webmqx_util).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("webmqx.hrl").

-export([env/1, words_to_path/1, path_to_words/1, 
		 env_vhost/0, env_username/0, env_password/0, env_rpc_workers_num/0]).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(env/1 :: (atom()) -> 'undefined' | any()).
-spec(env_vhost/0 :: () -> binary()).
-spec(env_username/0 :: () -> binary()).
-spec(env_password/0 :: () -> binary()).
-spec(env_rpc_workers_num/0 :: () -> non_neg_integer()).
-spec(words_to_path/1 :: ([string()]) -> binary()).
-spec(path_to_words/1 :: (binary()) -> [string()]). 

-endif.

%%----------------------------------------------------------------------------

%%%
%%% Exported functions
%%%

env(Key) ->
    case application:get_env(?APP, Key) of
        {ok, Val} -> Val;
        undefined -> undefined
    end.

env_username() ->
	case env(username) of
		undefined -> <<"guest">>;
		U -> U
	end.

env_password() ->
	case env(password) of
		undefined -> <<"guest">>;
		P -> P
	end.

env_vhost() ->
	case env(vhost) of
		undefined -> <<"/">>;
		V -> V 
	end.

env_rpc_workers_num() ->
	case env(rpc_workers_num) of
		undefined -> ?DEFAULT_RPC_WORKERS_NUM;
		Num -> Num
	end.

words_to_path(["/"]) -> <<"/">>;
words_to_path([]) -> <<"/">>;
words_to_path(Words) when is_list(Words)->
	words_to_path1(Words, []).

words_to_path1([], Acc) -> list_to_binary(lists:reverse(Acc));
words_to_path1([Word|Rest], Acc) ->
	words_to_path1(Rest, [Word | ["/" | Acc]]).

path_to_words(<<$/>>) ->
	["/"];
path_to_words(<<>>) ->
    ["/"];
path_to_words(Path) when is_binary(Path)->
    path_to_words1(Path, [], []).

path_to_words1(<<>>, [], Acc) ->
    lists:reverse(Acc);
path_to_words1(<<>>, Word, Acc) ->
    lists:reverse([lists:reverse(Word) | Acc]);
path_to_words1(<<$/, Rest/binary>>, [], Acc) ->
    path_to_words1(Rest, [], Acc);
path_to_words1(<<$/, Rest/binary>>, Word, Acc) ->
    path_to_words1(Rest, [], [lists:reverse(Word) | Acc]);
path_to_words1(<<C:8, Rest/binary>>, Word, Acc) ->
    path_to_words1(Rest, [C | Word], Acc).
