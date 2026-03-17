import gleam/erlang/process
import gleam/int
import gleam/io
import nanoglaw/agent
import nanoglaw/agent/tools
import nanoglaw/bus
import nanoglaw/channel/manager
import nanoglaw/config
import nanoglaw/provider/openai
import nanoglaw/session

/// Main entry point. Starts the full OTP actor tree:
///
/// 1. Message bus actor — decouples channels from the agent
/// 2. Session store actor — in-memory conversation state
/// 3. Agent actor — LLM agentic loop (call → tool → call → respond)
/// 4. Channel manager actor → Telegram channel (via telega polling)
/// 5. Outbound dispatcher process — bus outbound → channel manager
/// 6. Inbound dispatcher process — bus inbound → agent
pub fn main() {
  io.println("nanoglaw starting...")

  let cfg = config.from_env()

  // Validate
  case cfg.provider.api_key {
    "" -> {
      io.println(
        "Error: NANOGLAW_API_KEY not set. Set it to your LLM provider API key.",
      )
      halt(1)
    }
    _ -> Nil
  }

  case cfg.telegram.token {
    "" ->
      io.println(
        "Warning: NANOGLAW_TELEGRAM_TOKEN not set. Telegram channel disabled.",
      )
    _ -> Nil
  }

  // 1. Message bus
  let assert Ok(bus_subject) = bus.start()
  io.println("  [ok] Message bus started")

  // 2. Session store
  let assert Ok(session_store) = session.start()
  io.println("  [ok] Session store started")

  // 3. LLM provider
  let provider = openai.provider(cfg.provider.api_key, cfg.provider.base_url)
  io.println(
    "  [ok] Provider: "
    <> cfg.agent.model
    <> " via "
    <> cfg.provider.base_url,
  )

  // 4. Agent actor
  let tool_list = tools.default_tools()
  let assert Ok(agent_subject) =
    agent.start(cfg.agent, provider, tool_list, bus_subject, session_store)
  io.println(
    "  [ok] Agent (max_iterations="
    <> int.to_string(cfg.agent.max_iterations)
    <> ")",
  )

  // 5. Channel manager + Telegram
  let assert Ok(channel_manager) = manager.start(cfg, bus_subject)
  process.send(channel_manager, manager.StartChannels)
  io.println("  [ok] Channel manager started")

  // 6. Outbound dispatcher
  manager.start_outbound_dispatcher(bus_subject, channel_manager)
  io.println("  [ok] Outbound dispatcher started")

  // 7. Inbound dispatcher
  start_inbound_dispatcher(bus_subject, agent_subject)
  io.println("  [ok] Inbound dispatcher started")

  io.println("\nnanoglaw is running. Waiting for messages...")
  process.sleep_forever()
}

/// Spawn a process that routes inbound bus messages to the agent.
fn start_inbound_dispatcher(
  bus_subject: process.Subject(bus.BusMessage),
  agent_subject: process.Subject(agent.AgentMessage),
) -> Nil {
  process.spawn(fn() { inbound_loop(bus_subject, agent_subject) })
  Nil
}

fn inbound_loop(
  bus_subject: process.Subject(bus.BusMessage),
  agent_subject: process.Subject(agent.AgentMessage),
) -> Nil {
  let msg = bus.consume_inbound(bus_subject)
  process.send(agent_subject, agent.ProcessInbound(msg))
  inbound_loop(bus_subject, agent_subject)
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil
