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

-module (nrpc_worker).
-export([
		init_worker/6,
		init_worker/3
	]).
-export ([
		start_link_sup/1,
		start_link/6,
		start_link/3,

		start_worker/7,
		start_worker/4
	]).

start_worker( Sup, Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ) ->
	supervisor:start_child( Sup, [ Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ] ).
start_worker( Sup, Module, Function, Args ) ->
	supervisor:start_child( Sup, [ Module, Function, Args ] ).

start_link_sup( Name ) -> simplest_one_for_one:start_link( {local, list_to_atom( atom_to_list( Name ) ++ "_w_sup" )}, {?MODULE, start_link, []} ).
start_link( Module, Function, Args ) ->
	proc_lib:start_link( ?MODULE, init_worker, [ Module, Function, Args ] ).
start_link( Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ) ->
	proc_lib:start_link( ?MODULE, init_worker, [ Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ] ).

%% Cast worker
init_worker( Module, Function, Args ) ->
	proc_lib:init_ack({ok, self()}),
	try
		_Ignored = erlang:apply( Module, Function, Args )
	catch Error:Reason ->
		error_logger:warning_report([
				?MODULE, init_worker, cast_error,
				{Error, Reason}, {module, Module},
				{function, Function}, {args, Args}
			])
	end,
	ok.

%% Call worker
init_worker( Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ) ->
	proc_lib:init_ack( {ok, self()} ),
	erlang:group_leader( GroupLeader, self() ),
	Result =
		try {ok, erlang:apply( Module, Function, Args )}
		catch Error:Reason -> {Error, Reason} end,
	ok = nrpc_transmitter:push_reply( Transmitter, GenReplyTo, Result ).

