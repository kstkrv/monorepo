import orchestrator/tool.{type Tool}
import orchestrator/types.{type AgentConfig, type LlmResponse, type Message, type OrchestratorError}

/// A provider knows how to talk to an LLM API.
pub type Provider {
  Provider(
    name: String,
    /// Complete a chat: takes config, messages, tools and returns the LLM response.
    /// This encapsulates both the HTTP call and response parsing.
    chat: fn(AgentConfig, List(Message), List(Tool)) ->
      Result(LlmResponse, OrchestratorError),
  )
}
