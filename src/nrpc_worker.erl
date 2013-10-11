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
-export([init/1, init_worker/6]).
-export ([
		start_link_sup/0,
		start_link/6,

		start_worker/7
	]).

start_worker( Sup, Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ) ->
	supervisor:start_child( Sup, [ Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ] ).

start_link_sup() -> supervisor:start_link( ?MODULE, {} ).
start_link( Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ) ->
	proc_lib:start_link( ?MODULE, init_worker, [ Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ] ).

init( {} ) -> {ok, { {simple_one_for_one, 0, 1}, [
			{ undefined,
				{?MODULE, start_link, []},
				temporary, brutal_kill, worker, [ ?MODULE ] }
		] }}.

init_worker( Transmitter, GroupLeader, GenReplyTo, Module, Function, Args ) ->
	proc_lib:init_ack( {ok, self()} ),
	erlang:group_leader( GroupLeader, self() ),
	Result =
		try {ok, erlang:apply( Module, Function, Args )}
		catch Error:Reason -> {Error, Reason} end,
	ok = nrpc_transmitter:push_reply( Transmitter, GenReplyTo, Result ).
