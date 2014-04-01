-ifndef( nrpc_include_nrpc_hrl ).
-define(nrpc_include_nrpc_hrl, true).

-define(nrpc_default_window_size, 1000).

-type nrpc_aggregator_name() :: atom().
-type nrpc_aggregator_config_option() :: {term(), term()}.
-type nrpc_aggregator_config() :: [ nrpc_aggregator_config_option() ].

-record( nrpc_cast, {
			module :: atom(),
			function :: atom(),
			args :: [ term() ]
		} ).
-record( nrpc_call, {
			nrpc_name :: atom(),
			reply_to_pid :: pid(),
			reply_ref :: reference(),
			module :: atom(), function :: atom(), args :: [ term() ]
		} ).
-record( nrpc_reply, {
			result :: term(),
			gen_reply_to :: { pid(), reference() }
		} ).

-type nrpc_cast() :: #nrpc_cast{}.
-type nrpc_call() :: #nrpc_call{}.
-type nrpc_reply() :: #nrpc_reply{}.

-endif. % nrpc_include_nrpc_hrl
