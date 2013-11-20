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

-module (nrpc_monitor_srv).
-behaviour (gen_server).
-export ([start_link/0]).
-export ([
		init/1,
		handle_call/3,
		handle_cast/2,
		handle_info/2,
		terminate/2,
		code_change/3
	]).

start_link() -> gen_server:start_link( {local, ?MODULE}, ?MODULE, {}, [] ).

%%% %%%%%%%%%% %%%
%%% gen_server %%%
%%% %%%%%%%%%% %%%

-record(s, {
		w_count :: pos_integer(),
		w_sup :: pid(),
		w_pids :: array()
	}).

init( {} ) ->
	{ok, WCount} = application:get_env( nrpc, nrpc_monitor_srv_workers ),
	{ok, WSup} = simplest_one_for_one:start_link( {local, nrpc_monitor_srv_w_sup}, {nrpc_monitor_worker_srv, start_link, []} ),
	S0 = spawn_workers( #s{
			w_count = WCount,
			w_sup = WSup
		} ),
	{ok, S0}.
handle_call( {install_monitor, Monitoring, Monitored}, GenReplyTo, State )
		when is_pid( Monitoring )
		andalso is_pid(Monitored) 
	-> handle_call_install_monitor( Monitoring, Monitored, GenReplyTo, State );
handle_call( Call, GenReplyTo, State ) ->
	error_logger:warning_report([
		?MODULE, handle_call, 
		{bad_call, Call}, 
		{gen_reply_to, GenReplyTo},
		{state, State} ]),
	{reply, badarg, State}.
handle_cast( Cast, State ) ->
	error_logger:warning_report([
		?MODULE, handle_cast,
		{bad_cast, Cast},
		{state, State} ]),
	{noreply, State}.
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

spawn_workers( S0 = #s{ w_sup = WSup, w_count = WCount } ) ->
	S0 #s{
			w_pids = lists:foldl(
				fun( WIdx, WPids ) ->
					{ok, WPid} = supervisor:start_child( WSup, [] ),
					_MonRef = erlang:monitor( process, WPid ),
					array:set( WIdx, WPid, WPids )
				end,
				array:new(WCount), lists:seq(0, WCount - 1))
		}.

handle_call_install_monitor( Monitoring, Monitored, GenReplyTo, State = #s{ w_count = WCount } ) ->
	WIdx = erlang:phash2( Monitored, WCount ),
	WPid = get_worker_by_idx( WIdx, State ),
	gen_server:cast( WPid, {install_monitor, Monitoring, Monitored, GenReplyTo} ),
	{noreply, State}.

get_worker_by_idx( WIdx, #s{ w_pids = WPids } ) -> array:get( WIdx, WPids ).
