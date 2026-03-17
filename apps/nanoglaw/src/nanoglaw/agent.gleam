import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import nanoglaw/bus
import nanoglaw/bus/events.{type InboundMessage, OutboundMessage}
import nanoglaw/config.{type AgentConfig}
import nanoglaw/provider.{type Provider}
import nanoglaw/session
import nanoglaw/tool.{type Tool}
import nanoglaw/types.{
  type LlmResponse, type Message, type NanoglawError, MaxIterationsReached,
  TextMessage, ToolResultMessage, ToolUse, ToolUseMessage,
}

/// Messages the agent actor handles.
pub type AgentMessage {
  /// Process an inbound message from the bus.
  ProcessInbound(InboundMessage)
  /// Shutdown the agent.
  Shutdown
}

/// Agent state.
type AgentState {
  AgentState(
    config: AgentConfig,
    provider: Provider,
    tools: List(Tool),
    bus: Subject(bus.BusMessage),
    sessions: Subject(session.SessionMessage),
  )
}

/// Start the agent actor. It listens for inbound messages from the bus
/// and dispatches responses back.
pub fn start(
  config: AgentConfig,
  provider: Provider,
  tools: List(Tool),
  bus_subject: Subject(bus.BusMessage),
  session_store: Subject(session.SessionMessage),
) -> Result(Subject(AgentMessage), actor.StartError) {
  let state =
    AgentState(
      config:,
      provider:,
      tools:,
      bus: bus_subject,
      sessions: session_store,
    )

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
    ProcessInbound(msg) -> {
      handle_inbound(state, msg)
      actor.continue(state)
    }
  }
}

fn handle_inbound(state: AgentState, msg: InboundMessage) -> Nil {
  let cmd = string.trim(string.lowercase(msg.content))

  case cmd {
    "/new" -> {
      session.clear(state.sessions, events.session_key(msg))
      bus.publish_outbound(
        state.bus,
        OutboundMessage(
          channel: msg.channel,
          chat_id: msg.chat_id,
          content: "New session started.",
          metadata: dict.new(),
        ),
      )
    }
    "/help" -> {
      bus.publish_outbound(
        state.bus,
        OutboundMessage(
          channel: msg.channel,
          chat_id: msg.chat_id,
          content: "nanoglaw commands:\n/new — Start a new conversation\n/help — Show available commands",
          metadata: dict.new(),
        ),
      )
    }
    _ -> {
      let session_key = events.session_key(msg)
      let history = session.get_history(state.sessions, session_key)

      // Build messages: history + current user message
      let current = TextMessage(types.User, msg.content)
      let messages = list.append(history, [current])

      // Run the agent loop
      let result = run_loop(state, messages, 0)

      let response_content = case result {
        Ok(llm_response) ->
          case llm_response.content {
            Some(text) -> text
            None -> "I processed your request but have no text response."
          }
        Error(MaxIterationsReached) ->
          "I reached the maximum number of iterations without completing the task."
        Error(err) -> "Error: " <> format_error(err)
      }

      // Save conversation turn to session
      let new_messages = case result {
        Ok(llm_response) ->
          case llm_response.content {
            Some(text) -> [current, TextMessage(types.Assistant, text)]
            None -> [current]
          }
        Error(_) -> [current]
      }
      session.append_messages(state.sessions, session_key, new_messages)

      // Send response
      bus.publish_outbound(
        state.bus,
        OutboundMessage(
          channel: msg.channel,
          chat_id: msg.chat_id,
          content: response_content,
          metadata: msg.metadata,
        ),
      )
    }
  }
}

/// The agentic loop: call LLM, execute tools if needed, repeat.
fn run_loop(
  state: AgentState,
  messages: List(Message),
  iteration: Int,
) -> Result(LlmResponse, NanoglawError) {
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
) -> Result(LlmResponse, NanoglawError) {
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

fn format_error(err: NanoglawError) -> String {
  case err {
    types.ProviderError(status, body) ->
      "Provider error ("
      <> string.inspect(status)
      <> "): "
      <> string.slice(body, 0, 200)
    types.NetworkError(reason) -> "Network error: " <> reason
    types.DecodeError(reason) -> "Decode error: " <> reason
    types.ToolExecutionError(name, reason) ->
      "Tool error (" <> name <> "): " <> reason
    MaxIterationsReached -> "Max iterations reached"
    types.Timeout -> "Timeout"
    types.ConfigError(reason) -> "Config error: " <> reason
    types.TelegramError(reason) -> "Telegram error: " <> reason
  }
}
