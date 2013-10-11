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

-module (nrpc_transmitter).
-export ([
		start_link/3,
		push_call/6,
		push_reply/3
	]).
-export([
		init_it/3
	]).

-include("nrpc.hrl").

start_link( Config, Local, Remote ) -> proc_lib:start_link( ?MODULE, init_it, [ Config, Local, Remote ] ).
push_call( Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ) -> Transmitter ! {push_call, GroupLeader, GenReplyTo, Module, Function, Args}, ok.
push_reply( Transmitter, GenReplyTo, Result ) -> Transmitter ! {push_reply, GenReplyTo, Result}, ok.

-record(s, {
		local :: term(),
		remote :: term(),
		config :: nrpc_aggregator_config(),
		window_size :: pos_integer(),

		pending_tasks = [] :: [ nrpc_call() | nrpc_reply() ]
	}).

init_it( Config, Local, Remote ) ->
	% error_logger:info_report([ ?MODULE, starting, {local, Local}, {remote, Remote} ]),
	proc_lib:init_ack( {ok, self()} ),
	idle_loop( #s{
			local = Local,
			remote = Remote,
			config = Config,
			window_size = proplists:get_value( window_size, Config, ?nrpc_default_window_size )
		} ).

idle_loop( S = #s{ window_size = WS } ) ->
	receive
		{push_call, GroupLeader, GenReplyTo, Module, Function, Args} ->
			Deadline = now_ms() + WS,
			aggregating_loop( Deadline, S #s{ pending_tasks = [ {call, GroupLeader, GenReplyTo, Module, Function, Args } ] } );
		{push_reply, GenReplyTo, Result} ->
			Deadline = now_ms() + WS,
			aggregating_loop( Deadline, S #s{ pending_tasks = [ {reply, GenReplyTo, Result} ] } );
		Junk ->
			error_logger:warning_report([ ?MODULE, idle_loop, {got_junk, Junk} ]),
			idle_loop( S )
	end.

aggregating_loop( Deadline, S = #s{ pending_tasks = PendingTasks } ) ->
	MSecTillDeadline = max( Deadline - now_ms(), 0 ),
	receive
		{push_call, GroupLeader, GenReplyTo, Module, Function, Args} ->
			aggregating_loop( Deadline,
				S #s{ pending_tasks = [ {call, GroupLeader, GenReplyTo, Module, Function, Args} | PendingTasks ] } );
		{push_reply, GenReplyTo, Result} ->
			aggregating_loop( Deadline,
				S #s{ pending_tasks = [ {reply, GenReplyTo, Result} | PendingTasks ] } );
		Junk ->
			error_logger:warning_report([ ?MODULE, aggregating_loop, {got_junk, Junk} ]),
			aggregating_loop( Deadline, S )
	after MSecTillDeadline ->
		flush_tasks( S )
	end.

flush_tasks( S = #s{ remote = Remote, local = Local, pending_tasks = PendingTasks } ) ->
	% error_logger:info_report([ ?MODULE, flush_tasks, {local, Local}, {remote, Remote}, {tasks_count, length(PendingTasks)} ]),
	case nrpc_srv:tasks( Remote, Local, PendingTasks ) of
		ok -> ok;
		{Error, Reason} ->
			error_logger:warning_report( [ ?MODULE, flush_tasks, {Error, Reason} ] ),
			lists:foreach( fun
					({reply, _, _}) -> ok;
					({call, _, GenReplyTo, _, _, _}) -> _Ignored = gen_server:reply( GenReplyTo, {Error, Reason} ), ok
				end,
				PendingTasks )
	end,
	idle_loop( S #s{ pending_tasks = [] } ).


now_ms() ->
	{Mega, Sec, Micro} = now(),
	Mega * 1000000000 + Sec * 1000 + Micro div 1000.