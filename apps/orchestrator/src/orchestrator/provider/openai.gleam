import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import orchestrator/provider.{Provider}
import orchestrator/tool.{type Tool}
import orchestrator/types.{
  type AgentConfig, type LlmResponse, type Message, type OrchestratorError,
  DecodeError, LlmResponse, MaxTokens, NetworkError, ProviderError, Stop,
  TextMessage, ToolCall, ToolResultMessage, ToolUse, ToolUseMessage,
}

/// Create an OpenAI-compatible provider with a custom base URL.
pub fn provider(api_key: String, base_url: String) -> provider.Provider {
  Provider(name: "openai", chat: fn(config, messages, tools) {
    chat(api_key, base_url, config, messages, tools)
  })
}

/// OpenRouter preset (https://openrouter.ai/api/v1).
pub fn openrouter(api_key: String) -> provider.Provider {
  provider(api_key, "https://openrouter.ai/api/v1")
}

/// Local Ollama preset (http://localhost:11434/v1).
pub fn ollama() -> provider.Provider {
  provider("ollama", "http://localhost:11434/v1")
}

/// Ollama at a custom host.
pub fn ollama_at(host: String) -> provider.Provider {
  provider("ollama", host <> "/v1")
}

fn chat(
  api_key: String,
  base_url: String,
  config: AgentConfig,
  messages: List(Message),
  tools: List(Tool),
) -> Result(LlmResponse, OrchestratorError) {
  let body = encode_request_body(config, messages, tools)

  let assert Ok(req) = request.to(base_url <> "/chat/completions")
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("authorization", "Bearer " <> api_key)
    |> request.set_body(json.to_string(body))

  case httpc.send(req) {
    Error(_) -> Error(NetworkError("HTTP request failed"))
    Ok(response) ->
      case response.status {
        status if status >= 200 && status < 300 ->
          parse_response(response.body)
        status -> Error(ProviderError(status, response.body))
      }
  }
}

fn encode_request_body(
  config: AgentConfig,
  messages: List(Message),
  tools: List(Tool),
) -> json.Json {
  let all_messages = case config.system_prompt {
    "" -> messages
    prompt -> [TextMessage(types.System, prompt), ..messages]
  }

  let base = [
    #("model", json.string(config.model)),
    #("max_tokens", json.int(config.max_tokens)),
    #(
      "messages",
      json.preprocessed_array(list.map(all_messages, encode_message)),
    ),
  ]

  let base = case config.temperature {
    Some(t) -> [#("temperature", json.float(t)), ..base]
    None -> base
  }

  let base = case tools {
    [] -> base
    ts ->
      [#("tools", json.preprocessed_array(list.map(ts, encode_tool))), ..base]
  }

  json.object(base)
}

fn encode_message(message: Message) -> json.Json {
  case message {
    TextMessage(role, content) ->
      json.object([
        #("role", json.string(encode_role(role))),
        #("content", json.string(content)),
      ])
    ToolUseMessage(id, name, arguments) ->
      json.object([
        #("role", json.string("assistant")),
        #(
          "tool_calls",
          json.preprocessed_array([
            json.object([
              #("id", json.string(id)),
              #("type", json.string("function")),
              #(
                "function",
                json.object([
                  #("name", json.string(name)),
                  #("arguments", json.string(arguments)),
                ]),
              ),
            ]),
          ]),
        ),
      ])
    ToolResultMessage(tool_use_id, content, _is_error) ->
      json.object([
        #("role", json.string("tool")),
        #("tool_call_id", json.string(tool_use_id)),
        #("content", json.string(content)),
      ])
  }
}

fn encode_role(role: types.Role) -> String {
  case role {
    types.System -> "system"
    types.User -> "user"
    types.Assistant -> "assistant"
    types.Tool -> "tool"
  }
}

fn encode_tool(tool: Tool) -> json.Json {
  json.object([
    #("type", json.string("function")),
    #(
      "function",
      json.object([
        #("name", json.string(tool.name)),
        #("description", json.string(tool.description)),
        #("parameters", tool.parameters),
      ]),
    ),
  ])
}

// --- Response parsing ---

pub fn parse_response(body: String) -> Result(LlmResponse, OrchestratorError) {
  let choice_decoder = {
    use finish_reason <- decode.field("finish_reason", decode.string)
    use message <- decode.field("message", message_decoder())
    decode.success(#(finish_reason, message))
  }

  let decoder = {
    use choices <- decode.field("choices", decode.list(choice_decoder))
    decode.success(choices)
  }

  case json.parse(body, decoder) {
    Error(_) -> Error(DecodeError("Failed to parse response"))
    Ok(choices) ->
      case choices {
        [] -> Error(DecodeError("No choices in response"))
        [#(finish_reason, message), ..] ->
          Ok(LlmResponse(
            content: message.content,
            tool_calls: message.tool_calls,
            stop_reason: parse_finish_reason(finish_reason),
          ))
      }
  }
}

type ParsedMessage {
  ParsedMessage(content: Option(String), tool_calls: List(types.ToolCall))
}

fn message_decoder() -> decode.Decoder(ParsedMessage) {
  use content <- decode.optional_field(
    "content",
    None,
    decode.optional(decode.string),
  )
  use tool_calls <- decode.optional_field(
    "tool_calls",
    [],
    decode.list(tool_call_decoder()),
  )
  decode.success(ParsedMessage(content:, tool_calls:))
}

fn tool_call_decoder() -> decode.Decoder(types.ToolCall) {
  use id <- decode.field("id", decode.string)
  use function <- decode.field("function", function_decoder())
  decode.success(ToolCall(id, function.name, function.arguments))
}

type ParsedFunction {
  ParsedFunction(name: String, arguments: String)
}

fn function_decoder() -> decode.Decoder(ParsedFunction) {
  use name <- decode.field("name", decode.string)
  use arguments <- decode.field("arguments", decode.string)
  decode.success(ParsedFunction(name:, arguments:))
}

fn parse_finish_reason(reason: String) -> types.StopReason {
  case reason {
    "stop" -> Stop
    "tool_calls" -> ToolUse
    "length" -> MaxTokens
    _ -> Stop
  }
}
