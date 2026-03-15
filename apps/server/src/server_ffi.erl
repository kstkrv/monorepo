-module(server_ffi).
-export([read_client_js/0]).

read_client_js() ->
    Path = client_js_path(),
    case file:read_file(Path) of
        {ok, Bin} -> {ok, Bin};
        {error, _} -> {error, nil}
    end.

client_js_path() ->
    case os:getenv("CLIENT_JS_PATH") of
        false -> "../client/build/dev/javascript/client/client.mjs";
        Val -> Val
    end.
