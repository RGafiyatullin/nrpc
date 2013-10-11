-ifndef( nrpc_include_nrpc_hrl ).
-define(nrpc_include_nrpc_hrl, true).

-define(nrpc_default_window_size, 1000).

-type nrpc_aggregator_name() :: atom().
-type nrpc_aggregator_config_option() :: {term(), term()}.
-type nrpc_aggregator_config() :: [ nrpc_aggregator_config_option() ].

-type nrpc_call() :: { call, GenReplyTo :: {pid(), reference()}, Module :: atom(), Function :: atom(), Args :: [ term() ] }.
-type nrpc_reply() :: { reply, GenReplyTo :: {pid(), reference()}, Result :: term() }.

-endif. % nrpc_include_nrpc_hrl
