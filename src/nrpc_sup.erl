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
-export([start_link/0, init/1]).
-include("nrpc.hrl").

-spec start_link() -> {ok, pid()}.
start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, {}).

init({}) ->
	{ok, Aggregators} = application:get_env( nrpc, aggregators ),
	{ok,
			{{one_for_one, 5, 30}, [
				aggregator_child_spec( AggrName, AggrConfig )
				|| {AggrName, AggrConfig} <- Aggregators
			] ++ [
				{nrpc_monitor_srv,
					{nrpc_monitor_srv, start_link, []},
					permanent, 100000, worker, [ nrpc_monitor_srv ]}
			]}
		}.

-spec aggregator_child_spec( nrpc_aggregator_name(), nrpc_aggregator_config() ) ->
	{nrpc_aggregator_name(), 
		{nrpc_srv, start_link, [ nrpc_aggregator_name() | nrpc_aggregator_config() ]},
		permanent, pos_integer(), worker, [ nrpc_srv ]}.

aggregator_child_spec( Name, Config ) when is_atom(Name) and is_list(Config) ->
	{Name,
		{nrpc_srv, start_link, [ Name, Config ]},
		permanent, 100000, worker, [ nrpc_srv ]}.
