import gleam/option.{type Option}

/// Roles in a conversation.
pub type Role {
  System
  User
  Assistant
  Tool
}

/// A single message in a conversation.
pub type Message {
  TextMessage(role: Role, content: String)
  ToolUseMessage(id: String, name: String, arguments: String)
  ToolResultMessage(tool_use_id: String, content: String, is_error: Bool)
}

/// A tool call requested by the LLM.
pub type ToolCall {
  ToolCall(id: String, name: String, arguments: String)
}

/// What the LLM returned.
pub type LlmResponse {
  LlmResponse(
    content: Option(String),
    tool_calls: List(ToolCall),
    stop_reason: StopReason,
  )
}

pub type StopReason {
  Stop
  ToolUse
  MaxTokens
}

/// Errors that can occur throughout nanoglaw.
pub type NanoglawError {
  ProviderError(status: Int, body: String)
  NetworkError(reason: String)
  DecodeError(reason: String)
  ToolExecutionError(tool_name: String, reason: String)
  MaxIterationsReached
  Timeout
  ConfigError(reason: String)
  TelegramError(reason: String)
}
