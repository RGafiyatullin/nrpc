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

-module (nrpc_async_task_sup).
-export ([ start_link/0 ]).
-export ([
		async_task_start_child/3,
		async_task_start_link/3,
		async_task_init/3
	]).

start_link() ->
	simplest_one_for_one:start_link( {local, ?MODULE}, { ?MODULE, async_task_start_link, [] } ).

async_task_start_child( M, F, A ) ->
	supervisor:start_child( ?MODULE, [ M, F, A ] ).

async_task_start_link( M, F, A ) ->
	proc_lib:start_link( ?MODULE, async_task_init, [ M, F, A ] ).

async_task_init( M, F, A ) ->
	_ = proc_lib:init_ack( {ok, self()} ),
	erlang:apply( M, F, A ).