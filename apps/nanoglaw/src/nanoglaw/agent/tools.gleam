import gleam/dynamic/decode
import gleam/json
import nanoglaw/json_compat
import nanoglaw/tool.{type Tool, Tool}

/// Create the default set of agent tools.
pub fn default_tools() -> List(Tool) {
  [echo_tool(), current_time_tool()]
}

/// A simple echo tool — useful for testing and as a template.
fn echo_tool() -> Tool {
  Tool(
    name: "echo",
    description: "Echo back the input message. Useful for testing.",
    parameters: json.object([
      #("type", json.string("object")),
      #(
        "properties",
        json.object([
          #(
            "message",
            json.object([
              #("type", json.string("string")),
              #("description", json.string("The message to echo back")),
            ]),
          ),
        ]),
      ),
      #("required", json.preprocessed_array([json.string("message")])),
    ]),
    execute: fn(arguments) {
      let decoder = {
        use message <- decode.field("message", decode.string)
        decode.success(message)
      }
      case json_compat.parse(arguments, decoder) {
        Ok(message) -> Ok("Echo: " <> message)
        Error(_) -> Error("Failed to parse echo arguments")
      }
    },
  )
}

/// A tool that returns the current time.
fn current_time_tool() -> Tool {
  Tool(
    name: "current_time",
    description: "Get the current date and time in ISO 8601 format.",
    parameters: json.object([
      #("type", json.string("object")),
      #("properties", json.object([])),
    ]),
    execute: fn(_arguments) { Ok(current_iso_time()) },
  )
}

@external(erlang, "nanoglaw_ffi", "current_iso_time")
fn current_iso_time() -> String
