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
-export ([ start_link/0, enter_loop/1 ]).
-export ([ async_task_start_child/4 ]).

async_task_start_child( Sup, M, F, A ) ->
	Sup ! { start_child, M, F, A },
	ok.

start_link() ->
	proc_lib:start_link(?MODULE, enter_loop, [ self() ]).

enter_loop( Parent ) ->
	_ = proc_lib:init_ack({ok, self()}),
	erlang:process_flag(trap_exit, true),
	loop( Parent ).

loop( Parent ) ->
	receive
		{start_child, M, F, A} ->
			_ = proc_lib:spawn_link( M, F, A ),
			loop( Parent );
		
		{'EXIT', Parent, Reason} -> exit(Reason);

		{'EXIT', _, normal} -> loop( Parent );
		{'EXIT', Pid, Abnormal} ->
			proc_lib:spawn_link(error_logger, warning_report,
				[{?MODULE, loop, {exited, Pid}, {reason, Abnormal}}]),
			loop( Parent )
	end.

% async_task_start_link( M, F, A ) ->
% 	proc_lib:start_link( ?MODULE, async_task_init, [ M, F, A ] ).

% async_task_init( M, F, A ) ->
% 	_ = proc_lib:init_ack( {ok, self()} ),
% 	erlang:apply( M, F, A ).