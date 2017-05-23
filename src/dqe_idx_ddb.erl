-module(dqe_idx_ddb).
-behaviour(dqe_idx).

%% API exports
-export([init/0,
         lookup/4, lookup/5, lookup_tags/1,
         collections/0, metrics/1, metrics/3, namespaces/1, namespaces/2,
         tags/2, tags/3, values/3, values/4, expand/2,
         add/4, add/5, update/5,
         delete/4, delete/5]).

%%====================================================================
%% API functions
%%====================================================================


init() ->
    %% We do not need to initialize anything here.
    ok.

lookup(Q, Start, Finish, _G, Opts) ->
    {ok, [D]} = lookup(Q, Start, Finish, Opts),
    {ok, [{D, []}]}.

lookup({'in', B, undefined}, Start, Finish, _Opts) ->
    {ok, lookup_all(B, Start, Finish)};

lookup({'in', B, M}, Start, Finish, _Opts) ->
    {ok, [{B, M, [{Start, Finish, default}]}]};

lookup({'in', B, undefined, _Where}, Start, Finish, _Opts) ->
    {ok, lookup_all(B, Start, Finish)};

lookup({'in', B, M, _Where}, Start, Finish, Opts) ->
    lookup({'in', B, M}, Start, Finish, Opts).

lookup_tags(_) ->
    {ok, []}.

-spec expand(dqe_idx:bucket(), [dqe_idx:glob_metric()]) ->
                    {ok, {dqe_idx:bucket(), [dqe_idx:metric()]}}.
expand(Bkt, Globs) ->
    Ps1 = lists:map(fun glob_prefix/1, Globs),
    Ps2 = compress_prefixes(Ps1),
    case Ps2 of
        all ->
            {ok, Ms} = ddb_connection:list(Bkt),
            {ok, {Bkt, Ms}};
        _ ->
            Ms1 = [begin
                       {ok, Ms} = ddb_connection:list(Bkt, P),
                       [M || M <- Ms]
                   end || P <- Ps2],
            Ms2 = lists:usort(lists:flatten(Ms1)),
            Ms3 = [dproto:metric_to_list(M) || M <- Ms2],
            {ok, {Bkt, Ms3}}
    end.

metrics(Collection, Prefix, Depth)
  when Depth > 0,
       is_list(Prefix) ->
    Prefix1 = dproto:metric_from_list(Prefix),
    {ok, Metrics} = ddb_connection:list(Collection, Prefix1),
    N = length(Prefix),
    MetricLs = [dproto:metric_to_list(Metric) || Metric <- Metrics],
    Variants = [lists:sublist(ML, N + 1, Depth) || ML <- MetricLs,
                                                   length(ML) > N,
                                                   lists:prefix(Prefix, ML)],
    {ok, lists:usort(Variants)}.

collections() ->
    ddb_connection:list().

metrics(Bucket) ->
    {ok, Ms} = ddb_connection:list(Bucket),
    Ms1 = [dproto:metric_to_list(M) || M <- Ms],
    {ok, Ms1}.

namespaces(_) ->
    {ok, []}.

namespaces(_, _) ->
    {ok, []}.

tags(_, _) ->
    {ok, []}.

tags(_, _, _) ->
    {ok, []}.

values(_, _, _) ->
    {ok, []}.

values(_, _, _, _) ->
    {ok, []}.

add(_, _, _, _) ->
    {ok, 0}.

add(_, _, _, _, _) ->
    {ok, 0}.

update(_, _, _, _, _) ->
    {ok, 0}.

delete(_, _, _, _) ->
    ok.

delete(_, _, _, _, _) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

glob_prefix(G) ->
    glob_prefix(G, []).

glob_prefix([], Prefix) ->
    dproto:metric_from_list(lists:reverse(Prefix));
glob_prefix(['*' |_], Prefix) ->
    dproto:metric_from_list(lists:reverse(Prefix));
glob_prefix([E | R], Prefix) ->
    glob_prefix(R, [E | Prefix]).

compress_prefixes(Prefixes) ->
    compress_prefixes(lists:sort(Prefixes), []).

compress_prefixes([<<>> | _], _) ->
    all;
compress_prefixes([], R) ->
    R;
compress_prefixes([E], R) ->
    [E | R];
compress_prefixes([A, B | R], Acc) ->
    case binary:longest_common_prefix([A, B]) of
        L when L == byte_size(A) ->
            compress_prefixes([B | R], Acc);
        _ ->
            compress_prefixes([B | R], [A | Acc])
    end.

lookup_all(Bucket, Start, Finish) ->
    {ok, Ms} = ddb_connection:list(Bucket),
    [{Bucket, dproto:metric_to_list(M), [{Start, Finish, default}]} || M <- Ms].
