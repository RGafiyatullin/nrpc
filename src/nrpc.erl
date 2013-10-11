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
-include("nrpc.hrl").

-spec start() -> ok.
-spec stop() -> ok.

-type aggregator() :: {nrpc_aggregator_name(), node()} | nrpc_aggregator_name().
-spec call(
		Client :: aggregator(), Server :: aggregator(),
		Module :: atom(), Function :: atom(), Args :: [ term() ]
	) -> term().



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

