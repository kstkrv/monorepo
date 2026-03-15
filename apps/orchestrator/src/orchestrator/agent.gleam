import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import orchestrator/provider.{type Provider}
import orchestrator/tool.{type Tool}
import orchestrator/types.{
  type AgentConfig, type LlmResponse, type Message, type OrchestratorError,
  MaxIterationsReached, TextMessage, ToolResultMessage, ToolUse, ToolUseMessage,
}

pub type AgentResponse =
  Result(LlmResponse, OrchestratorError)

/// Messages the agent actor can receive.
pub type AgentMessage {
  Run(messages: List(Message), reply_to: Subject(AgentResponse))
  Shutdown
}

type AgentState {
  AgentState(config: AgentConfig, provider: Provider, tools: List(Tool))
}

/// Start a new agent actor.
pub fn start(
  config: AgentConfig,
  provider: Provider,
  tools: List(Tool),
) -> Result(Subject(AgentMessage), actor.StartError) {
  let state = AgentState(config:, provider:, tools:)

  let result =
    actor.new(state)
    |> actor.on_message(handle_message)
    |> actor.start

  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

fn handle_message(
  state: AgentState,
  message: AgentMessage,
) -> actor.Next(AgentState, AgentMessage) {
  case message {
    Shutdown -> actor.stop()
    Run(messages, reply_to) -> {
      let result = run_loop(state, messages, 0)
      process.send(reply_to, result)
      actor.continue(state)
    }
  }
}

/// The agentic loop: call LLM, execute tools if needed, repeat.
fn run_loop(
  state: AgentState,
  messages: List(Message),
  iteration: Int,
) -> AgentResponse {
  case iteration >= state.config.max_iterations {
    True -> Error(MaxIterationsReached)
    False ->
      case state.provider.chat(state.config, messages, state.tools) {
        Error(e) -> Error(e)
        Ok(llm_response) ->
          handle_llm_response(state, messages, llm_response, iteration)
      }
  }
}

fn handle_llm_response(
  state: AgentState,
  messages: List(Message),
  llm_response: LlmResponse,
  iteration: Int,
) -> AgentResponse {
  case llm_response.stop_reason {
    ToolUse -> {
      let tool_results =
        execute_tool_calls(state.tools, llm_response.tool_calls)
      let assistant_msg = case llm_response.content {
        Some(text) -> [TextMessage(types.Assistant, text)]
        None -> []
      }
      let tool_use_msgs =
        list.map(llm_response.tool_calls, fn(tc) {
          ToolUseMessage(tc.id, tc.name, tc.arguments)
        })
      let new_messages =
        list.flatten([messages, assistant_msg, tool_use_msgs, tool_results])
      run_loop(state, new_messages, iteration + 1)
    }
    _ -> Ok(llm_response)
  }
}

fn execute_tool_calls(
  tools: List(Tool),
  tool_calls: List(types.ToolCall),
) -> List(Message) {
  list.map(tool_calls, fn(tc) {
    case tool.execute(tools, tc.name, tc.arguments) {
      Ok(result) -> ToolResultMessage(tc.id, result, False)
      Error(reason) -> ToolResultMessage(tc.id, reason, True)
    }
  })
}
