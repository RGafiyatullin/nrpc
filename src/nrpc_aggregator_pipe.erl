% Copyright 2014 and onwards Roman Gafiyatullin
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

-module (nrpc_aggregator_pipe).
-behaviour (gen_pipe).
-export ([
		rx_init/1,
		rx_msg_in/2,

		tx_init/1,
		tx_on_rx_dn/2,
		tx_on_rx_up/2
	]).
-export ([
		process_call_task/1
	]).
-include("nrpc.hrl").

-record(tx, {}).
-record(rx, {}).

tx_init( { _Name, _Config } ) -> {ok, #tx{}}.
tx_on_rx_up( _RxPid, S = #tx{} ) -> S.
tx_on_rx_dn( _RxPid, S = #tx{} ) -> S.

rx_init( { _Name, _Config } ) -> {ok, #rx{}}.

rx_msg_in( #nrpc_cast{ module = M, function = F, args = A }, S = #rx{} ) ->
	_ = nrpc_async_task_sup:async_task_start_child( M, F, A ),
	S;
rx_msg_in( CallTask = #nrpc_call{}, S = #rx{} ) ->
	_ = nrpc_async_task_sup:async_task_start_child( ?MODULE, process_call_task, [CallTask] ),
	S;
rx_msg_in( UnexpectedMsg, S = #rx{} ) ->
	error_logger:warning_report([?MODULE, rx_msg_in, {unexpected_msg, UnexpectedMsg}]),
	S.


process_call_task( #nrpc_call{
	nrpc_name = _NRPCName,
	reply_to_pid = ReplyToPid, reply_ref = ReplyRef,
	module = M, function = F, args = A
} ) ->
	Executor = spawn( fun() ->
			receive start -> ok end,
			Result = erlang:apply( M, F, A ),
			exit( {ReplyRef, Result} )
		end ),
	ExecutorMonRef = erlang:monitor( process, Executor ),
	Executor ! start,
	receive
		{'DOWN', ExecutorMonRef, process, Executor, {ReplyRef, Result}} ->
			ReplyToPid ! {nrpc_reply, ReplyRef, Result};
		{'DOWN', ExecutorMonRef, process, Executor, Failure} ->
			ReplyToPid ! {nrpc_reply, ReplyRef, {error, Failure}}
	end.
