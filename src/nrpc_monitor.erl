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

-module (nrpc_monitor).
-export ([ install_monitor/2 ]).

-opaque mon_ref() :: reference().

-spec install_monitor( Monitoree :: pid(), Via :: atom() ) -> mon_ref().
install_monitor( Monitoree, Via )
	when is_pid( Monitoree ) andalso is_atom( Via )
->
	Observer = self(),
	ObserverNode = node( Observer ),
	MonitoreeNode = node( Monitoree ),
	case ObserverNode == MonitoreeNode of
		true -> erlang:monitor( process, Monitoree );
		false -> install_monitor_remote( Observer, ObserverNode, Monitoree, MonitoreeNode, Via )
	end.

-spec install_monitor_remote(
		Observer :: pid(), ObserverNode :: node(),
		Monitoree :: pid(), MonitoreeNode :: node(),
		Via :: atom()
	) -> mon_ref().

install_monitor_remote( Observer, _ObserverNode, Monitoree, MonitoreeNode, Via )
	when is_pid( Observer ) andalso is_atom( _ObserverNode )
	andalso is_pid( Monitoree ) andalso is_atom( MonitoreeNode )
	andalso is_atom( Via )
->
	case nrpc:call( MonitoreeNode, nrpc_monitor_srv, install_monitor, [ Via, Observer, Monitoree ] ) of
		{ok, MonRef} -> MonRef;
		{error, no_nrpc} ->
			SurrogateMonRef = erlang:make_ref(),
			Observer ! {'DOWN', SurrogateMonRef, process, Monitoree, no_nrpc},
			SurrogateMonRef
	end.

