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

-module(nrpc_sup).
-behaviour(supervisor).
-export ([ start_link/0, start_link_aggregators_sup/0 ]).
-export ([ add_aggregator/2, remove_aggregator/1 ]).
-export ([ init/1 ]).
-include("nrpc.hrl").

-spec start_link() -> {ok, pid()}.
start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, {sup}).
start_link_aggregators_sup() -> supervisor:start_link({local, nrpc_aggregator_sup}, ?MODULE, {aggregators_sup}).

add_aggregator( AggrName, AggrConfig ) ->
	supervisor:start_child( nrpc_aggregator_sup, aggregator_child_spec( AggrName, AggrConfig ) ).
remove_aggregator( AggrName ) ->
	ok = supervisor:terminate_child( nrpc_aggregator_sup, AggrName ),
	ok = supervisor:delete_child( nrpc_aggregator_sup, AggrName ).

init({sup}) -> init_nrpc_sup();
init({aggregators_sup}) -> init_aggregators_sup().

init_nrpc_sup() ->
	{ok,
			{{one_for_all, 5, 30}, 
				[
					{monitor_srv, {nrpc_monitor_srv, start_link, []},
						permanent, 10000, supervisor, []},
					{aggregators_sup, {?MODULE, start_link_aggregators_sup, []},
						permanent, infinity, supervisor, []}
				] }
		}.

init_aggregators_sup() ->
	{ok, Aggregators} = application:get_env( nrpc, aggregators ),
	ChildrenSpecs = [
		aggregator_child_spec( AggrName, AggrConfig )
		|| {AggrName, AggrConfig} <- Aggregators
	],
	{ok, { {one_for_one, 5, 30}, ChildrenSpecs }}.

aggregator_child_spec( Name, Config ) when is_atom(Name) and is_list(Config) ->
	{Name,
		{nrpc_aggregator_sup, start_link, [ Name, Config ]},
		permanent, 100000, worker, []}.


