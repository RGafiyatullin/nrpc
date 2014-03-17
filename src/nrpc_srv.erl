% Copyright 2013 and onwards Roman Gafiyatullin
%
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
%
%     http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
% 
% See the NOTICE file distributed with this work for additional information regarding copyright ownership.
% 

-module (nrpc_srv).
-behaviour(gen_server).
-export([
	start_link/2,
	tasks/3
]).
-export([
	init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3
]).
-include("nrpc.hrl").

-spec tasks(
		NRPC :: nrpc_aggregator_name(),
		ReplyToNRPC :: nrpc_aggregator_name(),
		Tasks :: [ nrpc_call() | nrpc_cast() | nrpc_reply() ]
	) ->
		ok | { error, nodedown | no_nrpc } | { exit | error | throw, term() }.
tasks( {_, RemoteNode} = NRPC, ReplyToNRPC, Tasks ) ->
	% error_logger:info_report( [?MODULE, tasks, {nrpc, NRPC}, {reply_to_nrpc, ReplyToNRPC}, {tasks, Tasks}] ),
	case nrpc:is_remote_alive(RemoteNode) of
		true ->
			try gen_server:call( NRPC, {tasks, ReplyToNRPC, Tasks}, infinity )
			catch
				exit:{{nodedown, _}, _} -> { error, nodedown };
				exit:{noproc, {gen_server, call, [ NRPC | _ ]} } -> { error, no_nrpc };
				exit:{timeout,{gen_server, call, [ NRPC | _]}} -> { error, timeout };
				Error:Reason ->
					error_logger:warning_report([?MODULE, tasks, {Error, Reason}]),
					{Error, Reason}
			end;
		false ->
			{ error, nodedown }
	end;
tasks( NRPC, ReplyToNRPC, Tasks ) ->
	try gen_server:call( NRPC, {tasks, ReplyToNRPC, Tasks}, infinity )
	catch
		exit:{{nodedown, _}, _} -> { error, nodedown };
		exit:{noproc, {gen_server, call, [ NRPC | _ ]} } -> { error, no_nrpc };
		exit:{timeout,{gen_server, call, [ NRPC | _]}} -> { error, timeout };
		Error:Reason ->
			error_logger:warning_report([?MODULE, tasks, {Error, Reason}]),
			{Error, Reason}
	end.


-spec start_link( Name :: nrpc_aggregator_name(), Config :: nrpc_aggregator_config() ) -> {ok, pid()}.
-spec start_link_sup( Name :: nrpc_aggregator_name(), Config :: nrpc_aggregator_config() ) -> {ok, pid()}.

start_link( Name, Config ) -> gen_server:start_link({local, Name}, ?MODULE, { Name, Config }, []).
start_link_sup( Name, Config ) -> simplest_one_for_one:start_link( {local, list_to_atom(atom_to_list( Name ) ++ "_t_sup")}, {nrpc_transmitter, start_link, [Config, Name]} ).

%%% %%%%%%%%%% %%%
%%% gen_server %%%
%%% %%%%%%%%%% %%%
-record(s, {
		name :: nrpc_aggregator_name(),
		config :: nrpc_aggregator_config(),
		sup :: pid(),
		w_sup :: pid()
	}).

init( {Name, Config} ) -> 
	{ok, Sup} = start_link_sup( Name, Config ),
	{ok, WSup} = nrpc_worker:start_link_sup( Name ),
	{ok, #s{
			name = Name,
			config = Config,
			sup = Sup,
			w_sup = WSup
		}}.
handle_call({call, GroupLeader, RemoteAggr, Module, Function, Args}, From, State) -> do_handle_call_call( RemoteAggr, GroupLeader, From, Module, Function, Args, State );
handle_call({tasks, ReplyToNRPC, Tasks}, _From, State0) ->
	{noreply, State1} = do_handle_call_tasks( ReplyToNRPC, Tasks, State0 ),
	{reply, ok, State1};
handle_call(Request, _From, State = #s{}) -> {stop, {bad_arg, Request}, State}.
handle_cast({cast, RemoteAggr, Module, Function, Args}, State) -> do_handle_cast_cast( RemoteAggr, Module, Function, Args, State );
handle_cast(Request, State = #s{}) -> {stop, {bad_arg, Request}, State}.
handle_info( {'DOWN', _MonRef, process, Pid, _}, State ) -> do_handle_info_down( Pid, State );
handle_info(Message, State = #s{}) -> {stop, {bad_arg, Message}, State}.
terminate(_Reason, _State) -> ignore.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%% %%%%%%%% %%%
%%% Internal %%%
%%% %%%%%%%% %%%
-define( transmitter_key( Remote ), {transmitter, Remote} ).
-define( transmitter_key_r( Pid ), {transmitter_r, Pid} ).

% handle a batch of tasks
do_handle_call_tasks( ReplyToNRPC, Tasks, State0 = #s{ w_sup = WSup } ) ->
	{ok, Transmitter, State1} = transmitter_get( ReplyToNRPC, State0 ),
	spawn_link( fun() ->
		do_handle_call_tasks_loop( Tasks, Transmitter, WSup )
	end),
	{noreply, State1}.

do_handle_call_tasks_loop( [], _Transmitter, _WSup ) -> ok;
do_handle_call_tasks_loop( [ {call, GroupLeader, GenReplyTo, Module, Function, Args} | Tasks ], Transmitter, WSup ) ->
	nrpc_worker:start_worker(
		WSup, Transmitter, GroupLeader,
		GenReplyTo, Module, Function, Args ),
	do_handle_call_tasks_loop( Tasks, Transmitter, WSup );
do_handle_call_tasks_loop( [ {cast, Module, Function, Args} | Tasks ], Transmitter, WSup ) ->
	nrpc_worker:start_worker( WSup, Module, Function, Args ),
	do_handle_call_tasks_loop( Tasks, Transmitter, WSup );
do_handle_call_tasks_loop( [ {reply, GenReplyTo, Result} | Tasks ], Transmitter, WSup ) ->
	_Ignored = gen_server:reply( GenReplyTo, Result ),
	do_handle_call_tasks_loop( Tasks, Transmitter, WSup ).

%% handle DOWN-messages (in case a transmitter dies)
do_handle_info_down( Pid, State = #s{ sup = Sup } ) ->
	case erlang:get( ?transmitter_key_r( Pid ) ) of
		undefined -> {noreply, State};
		Remote ->
			error_logger:warning_report( [ ?MODULE,
				transmitter_restarting, {remote, Remote}, {transmitter_dead, Pid} ] ),
			_ = transmitter_start( Sup, Remote ),
			{noreply, State}
	end.

do_handle_cast_cast( Remote, Module, Function, Args, State0 ) ->
	{ok, Transmitter, State1} = transmitter_get( Remote, State0 ),
	ok = nrpc_transmitter:push_cast( Transmitter, Module, Function, Args ),
	{noreply, State1}.


do_handle_call_call( Remote, GroupLeader, From, Module, Function, Args, State0 ) ->
	{ok, Transmitter, State1} = transmitter_get( Remote, State0 ),
	ok = nrpc_transmitter:push_call( Transmitter, GroupLeader, From, Module, Function, Args ),
	{noreply, State1}.

-spec transmitter_get( term(), #s{} ) -> {ok, pid(), #s{}}.
transmitter_get( Remote, State = #s{ sup = Sup } ) ->
	Transmitter = case erlang:get( ?transmitter_key( Remote ) ) of
		undefined -> transmitter_start( Sup, Remote );
		Pid when is_pid(Pid) -> Pid
	end,
	{ok, Transmitter, State}.

-spec transmitter_start( pid(), term() ) -> pid().
transmitter_start( Sup, Remote ) ->
	{ok, Transmitter} = supervisor:start_child( Sup, [ Remote ] ),
	erlang:put( ?transmitter_key( Remote ), Transmitter ),
	erlang:put( ?transmitter_key_r( Transmitter ), Remote ),
	erlang:monitor( process, Transmitter ),
	Transmitter.
