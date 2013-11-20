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

-module (nrpc).
-export([ start/0, stop/0 ]).
-export([ call/4, call/5, call_explicit/5 ]).
-export([ cast/4, cast/5, cast_explicit/5 ]).
-export([ monitor/1, monitor/2 ]).
-include("nrpc.hrl").

-spec start() -> ok.
-spec stop() -> ok.

-type aggregator() :: {nrpc_aggregator_name(), node()} | nrpc_aggregator_name().
-spec call_explicit(
		Client :: aggregator(), Server :: aggregator(),
		Module :: atom(), Function :: atom(), Args :: [ term() ]
	) -> term().
-spec cast_explicit(
		Client :: aggregator(), Server :: aggregator(),
		Module :: atom(), Function :: atom(), Args :: [ term() ]
	) -> ok.

-spec call( RemoteNode :: node(), NRPCName :: nrpc_aggregator_name(), Module :: atom(), Function :: atom(), Args :: [ term() ] ) -> term().
-spec call( RemoteNode :: node(), Module :: atom(), Function :: atom(), Args :: [ term() ] ) -> term().

-spec cast( RemoteNode :: node(), NRPCName :: nrpc_aggregator_name(), Module :: atom(), Function :: atom(), Args :: [ term() ] ) -> ok.
-spec cast( RemoteNode :: node(), Module :: atom(), Function :: atom(), Args :: [ term() ] ) -> ok.

start() -> application:start(nrpc).
stop() -> application:stop(nrpc).

call_explicit( ClientAggr, ServerAggr, Module, Function, Args ) ->
	case gen_server:call( ClientAggr, {call, erlang:group_leader(), ServerAggr, Module, Function, Args}, infinity ) of
		{ok, Result} -> Result;
		{Error, Reason}
			when Error == exit
			orelse Error == error
			orelse Error == throw
		->
			erlang:Error(Reason)
	end.


call( ThisNode, _, Module, Function, Args ) when ThisNode == node() -> erlang:apply( Module, Function, Args );
call( RemoteNode, NRPCName, Module, Function, Args )
	when is_atom( RemoteNode )
	andalso is_atom( NRPCName )
	andalso is_atom( Module )
	andalso is_atom( Function )
	andalso is_list( Args )
->
	call_explicit( {NRPCName, node()}, {NRPCName, RemoteNode}, Module, Function, Args ).

call( Node, Module, Function, Args ) -> call( Node, nrpc_default, Module, Function, Args ).

cast_explicit( ClientAggr, ServerAggr, Module, Function, Args ) ->
	gen_server:cast( ClientAggr, {cast, ServerAggr, Module, Function, Args} ).
cast( RemoteNode, NRPCName, Module, Function, Args )
	when is_atom( RemoteNode )
	andalso is_atom( NRPCName )
	andalso is_atom( Module )
	andalso is_atom( Function )
	andalso is_list( Args )
->
	cast_explicit( {NRPCName, node()}, {NRPCName, RemoteNode}, Module, Function, Args ).
cast( RemoteNode, Module, Function, Args ) -> cast( RemoteNode, nrpc_default, Module, Function, Args ).


-spec monitor( NRPCName :: nrpc_aggregator_name(), Monitored :: pid() ) -> reference().
-spec monitor( Monitored :: pid() ) -> reference().


monitor( Monitored ) -> ?MODULE:monitor( nrpc_default, Monitored ).
monitor( NRPCName, Monitored ) when is_pid( Monitored ) ->
	Monitoring = self(),
	MonitoredNode = node( Monitored ),
	case MonitoredNode == node() of
		true -> erlang:monitor( process, Monitored );
		false -> call( MonitoredNode, NRPCName, nrpc_monitor, install_monitor, [ Monitoring, Monitored ] )
	end.


