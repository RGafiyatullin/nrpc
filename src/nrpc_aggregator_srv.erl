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

-module (nrpc_aggregator_srv).
-behaviour (gen_server).
-export ([start_link/2]).
-export ([
		get_pipe_to_node/2,
		rpc_cast/5,
		rpc_call/6,
		rpc_reply/5
	]).
-export ([
		init/1,
		handle_call/3,
		handle_cast/2,
		handle_info/2,
		terminate/2,
		code_change/3
	]).
-include("nrpc.hrl").

start_link( Name, Config ) -> gen_server:start_link({local, Name}, ?MODULE, { Name, Config }, []).
-spec get_pipe_to_node( atom(), node() ) -> {ok, atom()} | {error, term()}.
get_pipe_to_node( Name, Node )
	when is_atom(Name) andalso is_atom( Node )
->
	try gen_server:call( Name, {get_pipe_to_node, Node} )
	catch
		exit:{noproc, {gen_server, call, [Name | _]}} -> {error, no_nrpc}
	end.

rpc_reply( NRPCName, RemoteNode, ReplyToPid, ReplyRef, Result )
	when is_atom( NRPCName ) andalso is_atom( RemoteNode )
	andalso is_pid( ReplyToPid ) andalso is_reference( ReplyRef )
->
	case get_pipe_to_node( NRPCName, RemoteNode ) of
		{ok, PipeTxName} ->
			case pipes:pass( PipeTxName, #nrpc_reply{ result = Result, reply_to_pid = ReplyToPid, reply_ref = ReplyRef } ) of
				ok -> ok;
				{error, rx_down} -> {error, rx_down}
			end;
		{error, Error} -> {error, Error}
	end.

rpc_cast( NRPCName, RemoteNode, Module, Function, Args )
	when is_atom( NRPCName ) andalso is_atom( RemoteNode )
	andalso is_atom( Module ) andalso is_atom( Function ) andalso is_list( Args )
->
	case get_pipe_to_node( NRPCName, RemoteNode ) of
		{ok, PipeTxName} ->
			case pipes:pass( PipeTxName, #nrpc_cast{ module = Module, function = Function, args = Args } ) of
				ok -> ok;
				{error, rx_down} -> {error, rx_down}
			end;
		{error, Error} -> {error, Error}
	end.
rpc_call( NRPCName, RemoteNode, Module, Function, Args, Timeout )
	when is_atom( NRPCName ) andalso is_atom( RemoteNode )
	andalso is_atom( Module ) andalso is_atom( Function ) andalso is_list( Args )
	andalso ( Timeout == infinity orelse ( is_integer(Timeout) andalso Timeout >= 0 ) )
->
	case get_pipe_to_node( NRPCName, RemoteNode ) of
		{ok, PipeTxName} ->
			ReplyReference = erlang:make_ref(),
			ReplyToPid = self(),
			case pipes:pass( PipeTxName, #nrpc_call{
					nrpc_name = NRPCName,
					reply_to_pid = ReplyToPid,
					reply_ref = ReplyReference,
					module = Module,
					function = Function,
					args = Args
				} )
			of
				ok -> rpc_call_wait_for_reply( ReplyReference, Timeout );
				{error, rx_down} -> {error, rx_down}
			end;
		{error, Error} -> {error, Error}
	end.

rpc_call_wait_for_reply( ReplyReference, infinity ) ->
	receive {nrpc_reply, ReplyReference, Result} -> Result end;

rpc_call_wait_for_reply( ReplyReference, Timeout ) when is_integer( Timeout ) andalso Timeout >= 0 ->
	receive {nrpc_reply, ReplyReference, Result} -> Result
	after Timeout -> {error, timeout} end.

-record(s, {
		name :: atom(),
		config :: term(),
		pipes = dict:new() :: dict()
	}).
init( { Name, Config } ) ->
	{ok, #s{
		name = Name,
		config = Config
	}}.

handle_call( {get_pipe_to_node, Node}, GenReplyTo, State ) ->
	handle_call_get_pipe_to_node( Node, GenReplyTo, State );

handle_call( Unexpected, GenReplyTo, State ) ->
	error_logger:warning_report([
			?MODULE, handle_call,
			{unexpected, Unexpected}, {gen_reply_to, GenReplyTo} ]),
	{reply, badarg, State}.

handle_cast( Unexpected, State ) ->
	error_logger:warning_report([
			?MODULE, handle_cast,
			{unexpected, Unexpected} ]),
	{noreply, State}.

handle_info( Unexpected, State ) ->
	error_logger:warning_info([
			?MODULE, handle_cast,
			{unexpected, Unexpected} ]),
	{noreply, State}.

terminate( _Reason, _State ) -> ignore.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%% Handlers 
handle_call_get_pipe_to_node( Node, _GenReplyTo, S0 = #s{ name = Name, pipes = Pipes0, config = Config } ) ->
	case dict:find( Node, Pipes0 ) of
		{ok, PipeName} -> {reply, {ok, PipeName}, S0};
		error ->
			PipeName = pipe_name( Name, Node ),
			PipeTx =
				case pipes:start_pipe( PipeName, Node, nrpc_aggregator_pipe, { Name, Config } ) of
					{ok, Pid} -> Pid;
					{error, already_started} -> erlang:whereis( PipeName )
				end,
			true = erlang:link( PipeTx ),
			Pipes1 = dict:store( Node, PipeName, Pipes0 ),
			S1 = S0 #s{ pipes = Pipes1 },
			{reply, {ok, PipeName}, S1}
	end.
	
pipe_name( Name, Node ) when is_atom( Name ) andalso is_atom( Node ) -> 
	list_to_atom(
		"nrpc_pipe[" ++ atom_to_list( Name )
		++ ":" ++ atom_to_list( Node ) ++ "]").

