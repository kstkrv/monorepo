import gleam/json.{type Json}
import gleam/list

/// A tool that an agent can use.
pub type Tool {
  Tool(
    name: String,
    description: String,
    /// JSON Schema for tool parameters (as pre-encoded JSON).
    parameters: Json,
    /// Execute the tool. Takes raw JSON arguments string, returns result or error.
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

/// Get a tool by name.
pub fn find(tools: List(Tool), name: String) -> Result(Tool, Nil) {
  list.find(tools, fn(t) { t.name == name })
}
