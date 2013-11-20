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

-module (nrpc_monitor_worker_srv).
-export ([start_link/0]).
-export ([notify_on_dead_process/3]).
-export ([
		init/1,
		handle_call/3,
		handle_cast/2,
		handle_info/2,
		terminate/2,
		code_change/3
	]).

start_link() -> gen_server:start_link( ?MODULE, {}, [] ).

%%% %%%%%%%%%% %%%
%%% gen_server %%%
%%% %%%%%%%%%% %%%

-record(s, {
		monitors = dict:new(),
		client_monitors = dict:new()
	}).

init( {} ) -> {ok, #s{}}.
handle_call( Call, GenReplyTo, State ) ->
	error_logger:warning_report([
		?MODULE, handle_call, 
		{bad_call, Call}, 
		{gen_reply_to, GenReplyTo},
		{state, State} ]),
	{reply, badarg, State}.
handle_cast( {install_monitor, Monitoring, Monitored, GenReplyTo}, State ) -> handle_cast_install_monitor( Monitoring, Monitored, GenReplyTo, State );
handle_cast( Cast, State ) ->
	error_logger:warning_report([
		?MODULE, handle_cast,
		{bad_cast, Cast},
		{state, State} ]),
	{noreply, State}.
handle_info( {'DOWN', MonRef, process, DeadPid, Reason}, State ) -> handle_info_down( MonRef, DeadPid, Reason, State );
handle_info( Info, State ) ->
	error_logger:warning_report([
		?MODULE, handle_info,
		{bad_info, Info},
		{state, State} ]),
	{noreply, State}.

terminate(_Reason, _State) -> ignore.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%% %%%%%%%% %%%
%%% Internal %%%
%%% %%%%%%%% %%%


notify_on_dead_process( DeadPid, Reason, Monitorings ) ->
	lists:foreach(
		fun( {CPid, CRef} ) ->
			nrpc:cast( node( CPid ), erlang, send, [ CPid, {'DOWN', CRef, process, DeadPid, Reason} ] )
		end,
		Monitorings).

handle_info_down( MonRef, DeadPid, Reason, State = #s{ monitors = CMs } ) ->
	case dict:find( DeadPid, CMs ) of
		error -> {noreply, State};
		{ok, MonRef} -> handle_info_down_monitored( DeadPid, Reason, State );
		{ok, _} -> {noreply, State}
	end.
handle_info_down_monitored( DeadPid, Reason, State0 = #s{ monitors = Ms0 } ) ->
	Ms1 = dict:erase( DeadPid, Ms0 ),
	State1 = notify_monitorings( DeadPid, Reason, State0 #s{ monitors = Ms1 } ),
	{noreply, State1}.

notify_monitorings( DeadPid, Reason, State0 = #s{ client_monitors = CMs0 } ) ->
	CMList = dict:fetch( DeadPid, CMs0 ),
	CMs1 = dict:erase( DeadPid, CMs0 ),
	_ = proc_lib:spawn_link( ?MODULE, notify_on_dead_process, [ DeadPid, Reason, CMList ] ),
	State0 #s{ client_monitors = CMs1 }.

handle_cast_install_monitor( Monitoring, Monitored, GenReplyTo, State0 ) ->
	{ClientMonRef, StateOut} =
		case is_already_monitored( Monitored, State0 ) of
			true ->
				add_monitoring_to_existing_monitored( Monitored, Monitoring, State0 );
			false ->
				State1 = add_monitored( Monitored, State0 ),
				add_monitoring_to_existing_monitored( Monitored, Monitoring, State1 )
		end,
	_Ignored = gen_server:reply( GenReplyTo, ClientMonRef ),
	{noreply, StateOut}.

is_already_monitored( Monitored, #s{ monitors = Monitors } ) ->
	case dict:find( Monitored, Monitors ) of
		{ok, _MonRef} -> true;
		error -> false
	end.

add_monitored( Monitored, State0 = #s{ monitors = Ms0, client_monitors = CMs0 } ) ->
	error = dict:find( Monitored, Ms0 ),
	MonRef = erlang:monitor( process, Monitored ),
	Ms1 = dict:store( Monitored, MonRef, Ms0 ),
	CMs1 = dict:store( Monitored, [], CMs0 ),
	State0 #s{ monitors = Ms1, client_monitors = CMs1 }.

add_monitoring_to_existing_monitored( Monitored, Monitoring, State0 = #s{ client_monitors = CMs0 } ) ->
	CRef = erlang:make_ref(),
	CMList0 = dict:fetch( Monitored, CMs0 ),
	CMList1 = [ {Monitoring, CRef} | CMList0 ],
	CMs1 = dict:store( Monitored, CMList1, CMs0 ),
	{CRef, State0 #s{ client_monitors = CMs1 }}.



