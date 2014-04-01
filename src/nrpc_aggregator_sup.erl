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

-module (nrpc_aggregator_sup).
-behaviour (supervisor).
-export ([start_link/2]).
-export ([init/1]).
start_link( Name, Config ) ->
	supervisor:start_link( {local, sup_name(Name)}, ?MODULE, { Name, Config } ).

init( {Name, Config} ) ->	
	{ok, { {one_for_all, 3, 10}, [
		{srv, {nrpc_aggregator_srv, start_link, [ Name, Config ]}, permanent, 10000, worker, [ nrpc_aggregator_srv ]}
	] }}.


%% internal 
sup_name( Name ) when is_atom(Name) -> list_to_atom(atom_to_list( Name ) ++ "_sup").
	