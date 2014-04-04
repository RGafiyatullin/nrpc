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
-export([ call/4, call/5, call/6 ]).
-export([ cast/4, cast/5 ]).
-export([ monitor/1, monitor/2 ]).
-export([ is_remote_alive/1 ]).
-export([ add/1, remove/1 ]).
-include("nrpc.hrl").

-spec start() -> ok.
-spec stop() -> ok.

start() -> application:start(nrpc).
stop() -> application:stop(nrpc).

add( Name ) when is_atom( Name ) -> nrpc_sup:add_aggregator( Name, [] ).
remove( Name ) when is_atom( Name ) -> nrpc_sup:remove_aggregator( Name ).

-spec cast( RemoteNode :: node(), NRPCName :: atom(), Module :: atom(), Function :: atom(), Args :: [ term() ] ) -> ok.
-spec cast( RemoteNode :: node(), Module :: atom(), Function :: atom(), Args :: [ term() ] ) -> ok.

cast( RemoteNode, Module, Function, Args ) -> cast( RemoteNode, nrpc_default, Module, Function, Args ).
cast( RemoteNode, NRPCName, Module, Function, Args )
	when is_atom( RemoteNode ) andalso is_atom( NRPCName )
	andalso is_atom( Module ) andalso is_atom( Function ) andalso is_list( Args )
	-> nrpc_aggregator_srv:rpc_cast( NRPCName, RemoteNode, Module, Function, Args ).

-type call_timeout() :: infinity | non_neg_integer().
-spec call( RemoteNode :: node(), Module :: atom(), Function :: atom(), Args :: [ term() ] ) -> term().
-spec call( RemoteNode :: node(), NRPCName :: atom(), Module :: atom(), Function :: atom(), Args :: [ term() ] ) -> term()
	;     ( RemoteNode :: node(), Module :: atom(), Function :: atom(), Args :: [ term() ], Timeout :: call_timeout() ) -> term().
-spec call( RemoteNode :: node(), NRPCName :: atom(), Module :: atom(), Function :: atom(), Args :: [ term() ], Timeout :: call_timeout() ) -> term().

call( RemoteNode, Module, Function, Args ) -> call( RemoteNode, nrpc_default, Module, Function, Args, infinity ).

call( RemoteNode, NRPCName, Module, Function, Args )
	when is_atom( RemoteNode ) andalso is_atom( NRPCName )
	andalso is_atom( Module ) andalso is_atom( Function ) andalso is_list( Args )
	-> call( RemoteNode, NRPCName, Module, Function, Args, infinity );

call( RemoteNode, Module, Function, Args, Timeout )
	when is_atom( RemoteNode )
	andalso is_atom( Module ) andalso is_atom( Function ) andalso is_list( Args )
	andalso ( Timeout == infinity orelse (is_integer( Timeout ) andalso Timeout >= 0) )
	-> call( RemoteNode, nrpc_default, Module, Function, Args, Timeout ).

call( LocalNode, _NRPCName, Module, Function, Args, _Timeout ) when node() == LocalNode ->
	try erlang:apply( Module, Function, Args )
	catch Error:Reason -> {error, {Error, Reason}} end;

call( RemoteNode, NRPCName, Module, Function, Args, Timeout )
	when is_atom( RemoteNode ) andalso is_atom( NRPCName )
	andalso is_atom( Module ) andalso is_atom( Function ) andalso is_list( Args )
	andalso ( Timeout == infinity orelse (is_integer( Timeout ) andalso Timeout >= 0) )
	-> nrpc_aggregator_srv:rpc_call( NRPCName, RemoteNode, Module, Function, Args, Timeout ).

is_remote_alive(RemoteNode) when RemoteNode == node() -> true;
is_remote_alive(RemoteNode) ->
	case net_kernel:node_info(RemoteNode) of
		{ok, NodeInfo} ->
			case proplists:get_value(state, NodeInfo) of
				up -> true;
				_ -> false
			end;
		_ -> false
	end.


% -spec monitor( NRPCName :: nrpc_aggregator_name(), Monitored :: pid() ) -> reference().
% -spec monitor( Monitored :: pid() ) -> reference().

monitor( Monitoree ) when is_pid( Monitoree ) -> nrpc_monitor:install_monitor( Monitoree, nrpc_default ).
monitor( Monitoree, NRPCName ) when is_pid( Monitoree ) andalso is_atom( NRPCName ) -> nrpc_monitor:install_monitor( Monitoree, NRPCName ).

% monitor( Monitored ) -> ?MODULE:monitor( nrpc_default, Monitored ).
% monitor( NRPCName, Monitored ) when is_pid( Monitored ) ->
% 	Monitoring = self(),
% 	MonitoredNode = node( Monitored ),
% 	case MonitoredNode == node() of
% 		true -> erlang:monitor( process, Monitored );
% 		false -> call( MonitoredNode, NRPCName, nrpc_monitor, install_monitor, [ Monitoring, Monitored ] )
% 	end.


