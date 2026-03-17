import nanoglaw/config.{type AgentConfig}
import nanoglaw/tool.{type Tool}
import nanoglaw/types.{type LlmResponse, type NanoglawError}

/// A provider knows how to talk to an LLM API.
/// Record-of-functions pattern allows easy swapping of providers.
pub type Provider {
  Provider(
    name: String,
    /// Complete a chat: takes config, messages, tools and returns the LLM response.
    chat: fn(AgentConfig, List(types.Message), List(Tool)) ->
      Result(LlmResponse, NanoglawError),
  )
}
