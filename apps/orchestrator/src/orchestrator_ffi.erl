-module(orchestrator_ffi).
-export([init_json_compat/0]).

-if(?OTP_RELEASE < 27).
%% On OTP < 27, compile a gleam_json_ffi replacement using thoas at runtime.
init_json_compat() ->
    Source = gleam_json_ffi_source(),
    {ok, Tokens, _} = erl_scan:string(Source),
    Forms = parse_forms(Tokens, []),
    {ok, gleam_json_ffi, Bin} = compile:forms(Forms, []),
    code:purge(gleam_json_ffi),
    {module, gleam_json_ffi} = code:load_binary(gleam_json_ffi, "gleam_json_ffi.erl", Bin),
    nil.

parse_forms(Tokens, Acc) ->
    case split_at_dot(Tokens) of
        {[], []} -> lists:reverse(Acc);
        {FormTokens, Rest} ->
            {ok, Form} = erl_parse:parse_form(FormTokens),
            parse_forms(Rest, [Form | Acc])
    end.

split_at_dot([]) -> {[], []};
split_at_dot([{dot, _} = Dot | Rest]) -> {[Dot], Rest};
split_at_dot([Token | Rest]) ->
    {Tokens, Remaining} = split_at_dot(Rest),
    {[Token | Tokens], Remaining}.

gleam_json_ffi_source() ->
    "-module(gleam_json_ffi).\n"
    "-export([decode/1, json_to_iodata/1, json_to_string/1,\n"
    "         int/1, float/1, string/1, bool/1, null/0, array/1, object/1]).\n"
    "\n"
    "decode(Json) ->\n"
    "    case thoas:decode(Json) of\n"
    "        {ok, Val} -> {ok, Val};\n"
    "        {error, _} -> {error, unexpected_end_of_input}\n"
    "    end.\n"
    "\n"
    "json_to_iodata(Json) -> Json.\n"
    "\n"
    "json_to_string(Json) when is_binary(Json) -> Json;\n"
    "json_to_string(Json) when is_list(Json) -> iolist_to_binary(Json).\n"
    "\n"
    "null() -> <<\"null\">>.\n"
    "bool(true) -> <<\"true\">>;\n"
    "bool(false) -> <<\"false\">>.\n"
    "int(X) -> integer_to_binary(X).\n"
    "float(X) -> float_to_binary(X, [{decimals, 20}, compact]).\n"
    "\n"
    "string(X) -> iolist_to_binary([34, escape_string(X), 34]).\n"
    "\n"
    "escape_string(<<>>) -> [];\n"
    "escape_string(<<34, Rest/binary>>) -> [92, 34 | escape_string(Rest)];\n"
    "escape_string(<<92, Rest/binary>>) -> [92, 92 | escape_string(Rest)];\n"
    "escape_string(<<10, Rest/binary>>) -> [92, $n | escape_string(Rest)];\n"
    "escape_string(<<13, Rest/binary>>) -> [92, $r | escape_string(Rest)];\n"
    "escape_string(<<9, Rest/binary>>) -> [92, $t | escape_string(Rest)];\n"
    "escape_string(<<C/utf8, Rest/binary>>) when C < 32 ->\n"
    "    [io_lib:format(\"\\\\u~4.16.0b\", [C]) | escape_string(Rest)];\n"
    "escape_string(<<C/utf8, Rest/binary>>) -> [<<C/utf8>> | escape_string(Rest)].\n"
    "\n"
    "array([]) -> <<\"[]\">>;\n"
    "array([First | Rest]) -> [91, First | array_loop(Rest)].\n"
    "array_loop([]) -> \"]\";\n"
    "array_loop([Elem | Rest]) -> [44, Elem | array_loop(Rest)].\n"
    "\n"
    "object(List) -> encode_object([[44, string(Key), 58 | Value] || {Key, Value} <- List]).\n"
    "encode_object([]) -> <<\"{}\">>;\n"
    "encode_object([[_Comma | Entry] | Rest]) -> [\"{\", Entry, Rest, \"}\"].\n".

-else.
init_json_compat() -> nil.
-endif.
