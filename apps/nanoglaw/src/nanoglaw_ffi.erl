-module(nanoglaw_ffi).
-export([split_commas/1, current_iso_time/0]).

%% Split a comma-separated string into a list of trimmed strings.
split_commas(Input) ->
    Parts = binary:split(Input, <<",">>, [global]),
    [string:trim(P) || P <- Parts, string:trim(P) =/= <<>>].

%% Return the current time as an ISO 8601 string.
current_iso_time() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:universal_time(),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
                                   [Y, Mo, D, H, Mi, S])).
