import gleam/json.{type Json}
import gleam/list

/// A tool that an agent can use.
pub type Tool {
  Tool(
    name: String,
    description: String,
    parameters: Json,
    execute: fn(String) -> Result(String, String),
  )
}

/// Execute a tool by name, looking it up from the registered tools.
pub fn execute(
  tools: List(Tool),
  name: String,
  arguments: String,
) -> Result(String, String) {
  case list.find(tools, fn(t) { t.name == name }) {
    Ok(tool) -> tool.execute(arguments)
    Error(_) -> Error("Unknown tool: " <> name)
  }
}
