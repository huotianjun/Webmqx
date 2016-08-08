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
%% Copyright (c) 2007-2015 Pivotal Software, Inc.  All rights reserved.
%%

-module(webmqx_table).

-export([create/0, create_local_copy/1, wait_for_replicated/0, wait/1,
         force_load/0, is_present/0, is_empty/0, needs_default_data/0,
         check_schema_integrity/0, clear_ram_only_tables/0, wait_timeout/0]).

%%----------------------------------------------------------------------------
%% Main interface
%%----------------------------------------------------------------------------

%%huotianjun 第一次启动，并且没有其他节点, 会create
%%huotianjun 如果需要从remote恢复，用create_local_copy
create() ->
    lists:foreach(fun ({Tab, TabDef}) ->
                          TabDef1 = proplists:delete(match, TabDef),
                          case mnesia:create_table(Tab, TabDef1) of
                              {atomic, ok} -> ok;
                              {aborted, Reason} ->
                                  throw({error, {table_creation_failed,
                                                 Tab, TabDef1, Reason}})
                          end
                  end, definitions()),
    ok.

%% The sequence in which we delete the schema and then the other
%% tables is important: if we delete the schema first when moving to
%% RAM mnesia will loudly complain since it doesn't make much sense to
%% do that. But when moving to disc, we need to move the schema first.
%% huotianjun 类型是本节点cluster的nodetype？
%% huotianjun 这个在rabbit_mnesia init_db中被调用，参数是当前节点的storage type
create_local_copy(disc) ->
	%%huotianjun 如果要设置disc，先schema，再其他
    create_local_copy(schema, disc_copies),
    create_local_copies(disc);
create_local_copy(ram)  ->
	%%huotianjun 如果是设置ram，先其他，再schema
    create_local_copies(ram),
    create_local_copy(schema, ram_copies).

wait_for_replicated() ->
    wait([Tab || {Tab, TabDef} <- definitions(),
				 %%huotianjun local_content是本地独有内容，不需要cluster？？？
                 not lists:member({local_content, true}, TabDef)]).

wait(TableNames) ->
    %% We might be in ctl here for offline ops, in which case we can't
    %% get_env() for the rabbit app.
    Timeout = wait_timeout(),
    case mnesia:wait_for_tables(TableNames, Timeout) of
        ok ->
            ok;
        {timeout, BadTabs} ->
            throw({error, {timeout_waiting_for_tables, BadTabs}});
        {error, Reason} ->
            throw({error, {failed_waiting_for_tables, Reason}})
    end.

wait_timeout() ->
    case application:get_env(hello_erlang, mnesia_table_loading_timeout) of
        {ok, T}   -> T;
        undefined -> 30000
    end.

%%huotianjun 在异常情况下，装载rabbitmq系统表？
force_load() -> [mnesia:force_load_table(T) || T <- names()], ok.

%%huotianjun 定义的表在系统中全了！
is_present() -> names() -- mnesia:system_info(tables) =:= [].

is_empty()           -> is_empty(names()).
needs_default_data() -> is_empty([]).

is_empty(Names) ->
    lists:all(fun (Tab) -> mnesia:dirty_first(Tab) == '$end_of_table' end,
              Names).

check_schema_integrity() ->
    Tables = mnesia:system_info(tables),
	%%huotianjun 比恩里所有定义的表，看有没有Error
    case check(fun (Tab, TabDef) ->
					   %%huotianjun 定义的表在不在Tables里面, 如果在，还要进一步check_attributes
                       case lists:member(Tab, Tables) of
                           false -> {error, {table_missing, Tab}};
                           true  -> check_attributes(Tab, TabDef)
                       end
               end) of
        ok     -> ok = wait(names()),
				  %%huotianjun 最后，还要检查内容
                  check(fun check_content/2);
        Other  -> Other
    end.

clear_ram_only_tables() ->
    Node = node(),
    lists:foreach(
      fun (TabName) ->
              case lists:member(Node, mnesia:table_info(TabName, ram_copies)) of
                  true  -> {atomic, ok} = mnesia:clear_table(TabName);
                  false -> ok
              end
      end, names()),
    ok.

%%--------------------------------------------------------------------
%% Internal helpers
%%--------------------------------------------------------------------

%%huotianjun 本地化创建除了根表schema以外的其他tables
create_local_copies(Type) ->
    lists:foreach(
      fun ({Tab, TabDef}) ->
              HasDiscCopies     = has_copy_type(TabDef, disc_copies),
              HasDiscOnlyCopies = has_copy_type(TabDef, disc_only_copies),
              LocalTab          = proplists:get_bool(local_content, TabDef),
              StorageType =
                  if
                      Type =:= disc orelse LocalTab ->
                          if
							  %%huotianjun 表定义与要求的Type必须一致，不一致，按照ram_copies？？？？
                              HasDiscCopies     -> disc_copies;
                              HasDiscOnlyCopies -> disc_only_copies;
                              true              -> ram_copies
                          end;
                      Type =:= ram ->
                          ram_copies
                  end,
              ok = create_local_copy(Tab, StorageType)
      end, definitions(Type)),
    ok.

%%huotianjun 向mnesia提交修改
%%huotianjun 例如 create_local_copy(schema, disc_copies),
%%huotianjun 这个是处理一个表。注意：schema是系统根表
%%huotianjun 在本节点复制或者更改storage type类型
create_local_copy(Tab, Type) ->
    StorageType = mnesia:table_info(Tab, storage_type),
	%%huotianjun
	%%storage_type. Returns the local storage type of the table. It can be disc_copies, ram_copies, disc_only_copies, or the atom unknown. unknown is returned for all tables that only reside remotely.
    {atomic, ok} =
        if
			%%huotianjun 这个说明Tab只存在于远方？
            StorageType == unknown ->
                mnesia:add_table_copy(Tab, node(), Type);

			%%huotianjun 本地有，改类型后，mnesia会自动同步！
            StorageType /= Type ->
				%%huotianjun 改变类型？
                mnesia:change_table_copy_type(Tab, node(), Type);
            true -> {atomic, ok}
        end,
    ok.

%%huotianjun
%%huotianjun 例如在表定义中，有这样 {disc_copies, [node()]},
has_copy_type(TabDef, DiscType) ->
    lists:member(node(), proplists:get_value(DiscType, TabDef, [])).

%%huotianjun 检查一下，定义的与实际是否一致
check_attributes(Tab, TabDef) ->
    {_, ExpAttrs} = proplists:lookup(attributes, TabDef),
    case mnesia:table_info(Tab, attributes) of
        ExpAttrs -> ok;
        Attrs    -> {error, {table_attributes_mismatch, Tab, ExpAttrs, Attrs}}
    end.

check_content(Tab, TabDef) ->
    {_, Match} = proplists:lookup(match, TabDef),
    case mnesia:dirty_first(Tab) of
        '$end_of_table' ->
            ok;
        Key ->
            ObjList = mnesia:dirty_read(Tab, Key),
            MatchComp = ets:match_spec_compile([{Match, [], ['$_']}]),
            case ets:match_spec_run(ObjList, MatchComp) of
                ObjList -> ok;
                _       -> {error, {table_content_invalid, Tab, Match, ObjList}}
            end
    end.

%%huotianjun 遍历所有定义的表，Fun一下，看有没有Error
check(Fun) ->
    case [Error || {Tab, TabDef} <- definitions(),
                   begin
                       {Ret, Error} = case Fun(Tab, TabDef) of
                           ok         -> {false, none};
                           {error, E} -> {true, E}
                       end,
                       Ret
                   end] of
        []     -> ok;
        Errors -> {error, Errors}
    end.

%%--------------------------------------------------------------------
%% Table definitions
%%--------------------------------------------------------------------

%%huotianjun rabbitmq的系统表？
names() -> [Tab || {Tab, _} <- definitions()].

%% The tables aren't supposed to be on disk on a ram node
definitions(disc) ->
    definitions();
definitions(ram) ->
    [{Tab, [{disc_copies, []}, {ram_copies, [node()]} |
			%%huotianjun 拼了两个元素，如果是拼连个list，用++
            proplists:delete(
              ram_copies, proplists:delete(disc_copies, TabDef))]} ||

        {Tab, TabDef} <- definitions()].

%%huotianjun rabbitmq的应用表在这里？
definitions() ->
    %%[{rabbit_user,
    %%  [{record_name, internal_user},
    %%  {attributes, record_info(fields, internal_user)},
    %% {disc_copies, [node()]},
    %%   {match, #internal_user{_='_'}}]},
    %% {rabbit_vhost,
    %%		[{record_name, vhost},
    %% {attributes, record_info(fields, vhost)},
    %%		{disc_copies, [node()]},
    %%		{match, #vhost{_='_'}}]},
    %% {rabbit_queue,
    %%  [{record_name, amqqueue},
    %%   {attributes, record_info(fields, amqqueue)},
    %%  {match, #amqqueue{name = queue_name_match(), _='_'}}]}]
	%% ++
	%%huotianjun gm和mirrored_supervisor都建了一些表
        hello_rpc_ports:table_definitions() ++ hello_gm:table_definitions().
        %%++ mirrored_supervisor:table_definitions().
