-module (nrpc_monitor_srv).
-behaviour (gen_server).

-export ([ start_link/0 ]).
-export ([ install_monitor/3 ]).
-export ([ dispatch_down_msg/4 ]).
-export ([
		init/1,
		handle_call/3,
		handle_cast/2,
		handle_info/2,
		terminate/2,
		code_change/3
	]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, {}, []).
install_monitor( Via, Observer, Monitoree )
	when is_atom( Via )
	andalso is_pid( Observer ) andalso node() /= node(Observer)
	andalso is_pid( Monitoree ) andalso node() == node(Monitoree)
->
	try gen_server:call( ?MODULE, {install_monitor, Via, Observer, Monitoree} )
	catch
		exit:{norpoc, {gen_server, call, [ ?MODULE | _ ]}} -> {error, no_nrpc}
	end.

dispatch_down_msg( Observer, MonRef, DeadPid, DownReason )
	when is_reference( MonRef ) 
	andalso is_pid( Observer ) andalso node(Observer) == node()
	andalso is_pid( DeadPid ) andalso node( DeadPid ) /= node()
->
	Observer ! {'DOWN', MonRef, process, DeadPid, DownReason}.

-define(tab, ?MODULE).
-record(s, {}).

init( {} ) ->
	?tab = ets:new( ?tab, [ named_table, protected, set ] ),
	{ok, #s{}}.

handle_call( {install_monitor, Via, Observer, Monitoree}, GenReplyTo, State )
	when is_atom( Via )
	andalso is_pid( Observer ) andalso node() /= node(Observer)
	andalso is_pid( Monitoree ) andalso node() == node(Monitoree)
-> handle_call_install_monitor( Via, Observer, Monitoree, GenReplyTo, State );

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

handle_info( {'DOWN', MonRef, process, DeadPid, DownReason}, State )
	when is_reference( MonRef )
	andalso is_pid( DeadPid )
->
	handle_info_down( MonRef, DeadPid, DownReason, State );

handle_info( Unexpected, State ) ->
	error_logger:warning_info([
			?MODULE, handle_cast,
			{unexpected, Unexpected} ]),
	{noreply, State}.

terminate( _Reason, _State ) -> ignore.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%% Handlers 
handle_call_install_monitor( Via, Observer, Monitoree, _GenReplyTo, State ) ->
	MonRef = erlang:monitor( process, Monitoree ),
	true = ets:insert_new( ?tab, {MonRef, Observer, Via} ),
	{reply, {ok, MonRef}, State}.

handle_info_down( MonRef, DeadPid, DownReason, State ) ->
	case ets:lookup( ?tab, MonRef ) of
		[] -> {noreply, State};
		[ EtsRecord = {MonRef, Observer, Via} ] ->
			true = ets:delete_object( ?tab, EtsRecord ),
			_ = nrpc:cast( node(Observer), Via, ?MODULE, dispatch_down_msg, [ Observer, MonRef, DeadPid, DownReason ] ),
			{noreply, State}
	end.

