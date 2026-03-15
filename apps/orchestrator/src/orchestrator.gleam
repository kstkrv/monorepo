import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import orchestrator/agent.{type AgentMessage, type AgentResponse}
import orchestrator/provider.{type Provider}
import orchestrator/tool.{type Tool}
import orchestrator/types.{type AgentConfig, type Message}

/// Initialize the orchestrator runtime. Must be called once before any other
/// orchestrator function. Sets up JSON compatibility for the current OTP version.
pub fn init() -> Nil {
  init_json_compat()
}

@external(erlang, "orchestrator_ffi", "init_json_compat")
fn init_json_compat() -> Nil

/// Start a new agent actor.
pub fn start_agent(
  config: AgentConfig,
  provider: Provider,
  tools: List(Tool),
) -> Result(Subject(AgentMessage), actor.StartError) {
  agent.start(config, provider, tools)
}

/// Send messages to an agent and wait for the response.
pub fn call(
  agent: Subject(AgentMessage),
  messages: List(Message),
  timeout: Int,
) -> AgentResponse {
  actor.call(agent, timeout, agent.Run(messages, _))
}

/// Stop an agent.
pub fn stop(agent: Subject(AgentMessage)) -> Nil {
  process.send(agent, agent.Shutdown)
}
