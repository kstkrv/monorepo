-module(e2e_ffi).
-export([get_env/2, halt/1]).

get_env(Name, Default) ->
    case os:getenv(binary_to_list(Name)) of
        false -> Default;
        Value -> list_to_binary(Value)
    end.

halt(Code) ->
    erlang:halt(Code).
