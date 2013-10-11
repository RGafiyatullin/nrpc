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

-spec tasks( NRPC :: nrpc_aggregator_name(), ReplyToNRPC :: nrpc_aggregator_name(), Tasks :: [ nrpc_call() | nrpc_reply() ] ) -> ok.
tasks( NRPC, ReplyToNRPC, Tasks ) ->
	gen_server:cast( NRPC, {tasks, ReplyToNRPC, Tasks} ).


-spec start_link( Name :: nrpc_aggregator_name(), Config :: nrpc_aggregator_config() ) -> {ok, pid()}.
-spec start_link_sup( Name :: nrpc_aggregator_name(), Config :: nrpc_aggregator_config() ) -> {ok, pid()}.

start_link( Name, Config ) -> gen_server:start_link({local, Name}, ?MODULE, { server, Name, Config }, []).
start_link_sup( Name, Config ) -> supervisor:start_link( ?MODULE, { supervisor, Name, Config } ).

%%% %%%%%%%%%% %%%
%%% gen_server %%%
%%% %%%%%%%%%% %%%
-record(s, {
		name :: nrpc_aggregator_name(),
		config :: nrpc_aggregator_config(),
		sup :: pid()
	}).

init({supervisor, Name, Config}) -> supervisor_init( Name, Config );
init({server, Name, Config}) -> gen_server_init( Name, Config ).

supervisor_init( Name, Config ) ->
	{ok, { {simple_one_for_one, 0, 1}, [
			{ undefined,
				{nrpc_transmitter, start_link, [ Config, Name ]},
				temporary, 10000, worker, [ nrpc_transmitter ] }
		] }}.

-spec gen_server_init( nrpc_aggregator_name(), nrpc_aggregator_config() ) -> {ok, #s{}}.
gen_server_init( Name, Config ) -> 
	{ok, Sup} = start_link_sup( Name, Config ),
	{ok, #s{
			name = Name,
			config = Config,
			sup = Sup
		}}.
handle_call({call, RemoteAggr, Module, Function, Args}, From, State) -> do_handle_call_call( RemoteAggr, From, Module, Function, Args, State );
handle_call(Request, _From, State = #s{}) -> {stop, {bad_arg, Request}, State}.
handle_cast({tasks, ReplyToNRPC, Tasks}, State = #s{}) -> do_handle_cast_tasks( ReplyToNRPC, Tasks, State );
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

do_handle_cast_tasks( ReplyToNRPC, Tasks, State0 = #s{} ) ->
	{ok, Transmitter, State1} = transmitter_get( ReplyToNRPC, State0 ),
	spawn( fun() ->
		do_handle_cast_tasks_loop( Tasks, Transmitter )
	end),
	{noreply, State1}.

do_handle_cast_tasks_loop( [], _Transmitter ) -> ok;
do_handle_cast_tasks_loop( [ {call, GenReplyTo, Module, Function, Args} | Tasks ], Transmitter ) ->
	spawn( fun() ->
			Result =
				try {ok, erlang:apply( Module, Function, Args )}
				catch Error:Reason -> {Error, Reason} end,
			ok = nrpc_transmitter:push_reply( Transmitter, GenReplyTo, Result )
		end ),
	do_handle_cast_tasks_loop( Tasks, Transmitter );
do_handle_cast_tasks_loop( [ {reply, GenReplyTo, Result} | Tasks ], Transmitter ) ->
	_Ignored = gen_server:reply( GenReplyTo, Result ),
	do_handle_cast_tasks_loop( Tasks, Transmitter ).

do_handle_info_down( Pid, State = #s{ sup = Sup } ) ->
	case erlang:get( ?transmitter_key_r( Pid ) ) of
		undefined -> {noreply, State};
		Remote ->
			error_logger:warning_report( [ ?MODULE,
				transmitter_restarting, {remote, Remote}, {transmitter_dead, Pid} ] ),
			_ = transmitter_start( Sup, Remote ),
			{noreply, State}
	end.

do_handle_call_call( Remote, From, Module, Function, Args, State0 ) ->
	{ok, Transmitter, State1} = transmitter_get( Remote, State0 ),
	ok = nrpc_transmitter:push_call( Transmitter, From, Module, Function, Args ),
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
