import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import nanoglaw/agent
import nanoglaw/agent/tools
import nanoglaw/bus
import nanoglaw/bus/events.{InboundMessage, OutboundMessage}
import nanoglaw/channel/telegram.{MessageEntity}
import nanoglaw/config.{type AgentConfig, type TelegramConfig, AgentConfig, TelegramConfig}
import nanoglaw/json_compat
import nanoglaw/provider.{Provider}
import nanoglaw/provider/openai
import nanoglaw/session
import nanoglaw/tool
import nanoglaw/types.{Stop, ToolUse}

pub fn main() {
  gleeunit.main()
}

// --- Bus tests ---

pub fn bus_publish_consume_inbound_test() {
  let assert Ok(bus_subject) = bus.start()

  let msg =
    InboundMessage(
      channel: "test",
      sender_id: "user1",
      chat_id: "chat1",
      content: "hello",
      metadata: dict.new(),
    )

  bus.publish_inbound(bus_subject, msg)
  let received = bus.consume_inbound(bus_subject)

  received.content |> should.equal("hello")
  received.channel |> should.equal("test")
}

pub fn bus_publish_consume_outbound_test() {
  let assert Ok(bus_subject) = bus.start()

  let msg =
    OutboundMessage(
      channel: "test",
      chat_id: "chat1",
      content: "response",
      metadata: dict.new(),
    )

  bus.publish_outbound(bus_subject, msg)
  let received = bus.consume_outbound(bus_subject)

  received.content |> should.equal("response")
}

pub fn bus_waiter_pattern_test() {
  let assert Ok(bus_subject) = bus.start()

  // Spawn a consumer that blocks waiting for a message
  let test_subject = process.new_subject()
  process.spawn(fn() {
    let msg = bus.consume_inbound(bus_subject)
    process.send(test_subject, msg.content)
  })

  // Small delay to ensure consumer is waiting
  process.sleep(50)

  // Publish after consumer is already waiting
  bus.publish_inbound(
    bus_subject,
    InboundMessage(
      channel: "test",
      sender_id: "u1",
      chat_id: "c1",
      content: "delayed",
      metadata: dict.new(),
    ),
  )

  let assert Ok(result) = process.receive(test_subject, 2000)
  result |> should.equal("delayed")
}

// --- Session tests ---

pub fn session_get_or_create_test() {
  let assert Ok(store) = session.start()

  let s = session.get_or_create(store, "test:chat1")
  s.key |> should.equal("test:chat1")
  s.messages |> should.equal([])
}

pub fn session_append_and_get_history_test() {
  let assert Ok(store) = session.start()

  let _s = session.get_or_create(store, "test:chat1")
  session.append_messages(store, "test:chat1", [
    types.TextMessage(types.User, "hi"),
    types.TextMessage(types.Assistant, "hello"),
  ])

  let history = session.get_history(store, "test:chat1")
  history
  |> should.equal([
    types.TextMessage(types.User, "hi"),
    types.TextMessage(types.Assistant, "hello"),
  ])
}

pub fn session_clear_test() {
  let assert Ok(store) = session.start()

  let _s = session.get_or_create(store, "test:chat1")
  session.append_messages(store, "test:chat1", [
    types.TextMessage(types.User, "hi"),
  ])
  session.clear(store, "test:chat1")

  let history = session.get_history(store, "test:chat1")
  history |> should.equal([])
}

pub fn session_multiple_keys_test() {
  let assert Ok(store) = session.start()

  session.append_messages(store, "telegram:100", [
    types.TextMessage(types.User, "msg1"),
  ])
  session.append_messages(store, "telegram:200", [
    types.TextMessage(types.User, "msg2"),
  ])

  let h1 = session.get_history(store, "telegram:100")
  let h2 = session.get_history(store, "telegram:200")

  case h1 {
    [types.TextMessage(_, content)] -> content |> should.equal("msg1")
    _ -> should.fail()
  }
  case h2 {
    [types.TextMessage(_, content)] -> content |> should.equal("msg2")
    _ -> should.fail()
  }
}

pub fn session_get_history_nonexistent_test() {
  let assert Ok(store) = session.start()

  let history = session.get_history(store, "nonexistent")
  history |> should.equal([])
}

// --- Session key tests ---

pub fn session_key_test() {
  let msg =
    InboundMessage(
      channel: "telegram",
      sender_id: "123",
      chat_id: "456",
      content: "test",
      metadata: dict.new(),
    )
  events.session_key(msg) |> should.equal("telegram:456")
}

// --- Tool tests ---

pub fn tool_execute_known_test() {
  let test_tools = tools.default_tools()
  let assert Ok(result) = tool.execute(test_tools, "echo", "{\"message\":\"hi\"}")
  result |> should.equal("Echo: hi")
}

pub fn tool_execute_unknown_test() {
  let test_tools = tools.default_tools()
  let assert Error(reason) = tool.execute(test_tools, "nonexistent", "{}")
  reason |> should.equal("Unknown tool: nonexistent")
}

pub fn tool_find_existing_test() {
  let test_tools = tools.default_tools()
  let assert Ok(t) = tool.find(test_tools, "echo")
  t.name |> should.equal("echo")
}

pub fn tool_find_missing_test() {
  let test_tools = tools.default_tools()
  tool.find(test_tools, "nope") |> should.be_error()
}

// --- Agent tools tests ---

pub fn echo_tool_test() {
  let test_tools = tools.default_tools()
  let assert Ok(result) =
    tool.execute(test_tools, "echo", "{\"message\":\"hello world\"}")
  result |> should.equal("Echo: hello world")
}

pub fn echo_tool_bad_args_test() {
  let test_tools = tools.default_tools()
  let assert Error(_) = tool.execute(test_tools, "echo", "{}")
}

pub fn current_time_tool_test() {
  let test_tools = tools.default_tools()
  let assert Ok(result) = tool.execute(test_tools, "current_time", "{}")
  // Should return ISO 8601 format like "2026-03-16T22:00:00Z"
  string.contains(result, "T") |> should.be_true()
  string.contains(result, "Z") |> should.be_true()
}

// --- Provider response parsing tests ---

pub fn parse_text_response_test() {
  let body =
    "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\"Hello!\"}}]}"
  let assert Ok(response) = openai.parse_response(body)
  response.content |> should.equal(Some("Hello!"))
  response.stop_reason |> should.equal(Stop)
  response.tool_calls |> should.equal([])
}

pub fn parse_tool_call_response_test() {
  let body =
    "{\"choices\":[{\"finish_reason\":\"tool_calls\",\"message\":{\"content\":null,\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"echo\",\"arguments\":\"{\\\"message\\\":\\\"test\\\"}\"}}]}}]}"
  let assert Ok(response) = openai.parse_response(body)
  response.stop_reason |> should.equal(ToolUse)
  response.content |> should.equal(None)
  case response.tool_calls {
    [tc] -> {
      tc.id |> should.equal("call_1")
      tc.name |> should.equal("echo")
    }
    _ -> should.fail()
  }
}

pub fn parse_empty_choices_test() {
  let body = "{\"choices\":[]}"
  openai.parse_response(body) |> should.be_error()
}

pub fn parse_invalid_json_test() {
  openai.parse_response("not json") |> should.be_error()
}

pub fn parse_max_tokens_response_test() {
  let body =
    "{\"choices\":[{\"finish_reason\":\"length\",\"message\":{\"content\":\"truncated...\"}}]}"
  let assert Ok(response) = openai.parse_response(body)
  response.stop_reason |> should.equal(types.MaxTokens)
  response.content |> should.equal(Some("truncated..."))
}

// --- json_compat tests ---

pub fn json_compat_parse_string_test() {
  let decoder = {
    use name <- decode.field("name", decode.string)
    decode.success(name)
  }
  let assert Ok(val) = json_compat.parse("{\"name\":\"test\"}", decoder)
  val |> should.equal("test")
}

pub fn json_compat_parse_invalid_test() {
  json_compat.parse("not json", decode.string)
  |> should.be_error()
}

// --- Telegram allowlist tests ---

pub fn is_allowed_wildcard_test() {
  telegram.is_allowed(["*"], "12345|bob") |> should.be_true()
}

pub fn is_allowed_by_compound_id_test() {
  telegram.is_allowed(["12345|bob"], "12345|bob") |> should.be_true()
}

pub fn is_allowed_by_user_id_test() {
  telegram.is_allowed(["12345"], "12345|bob") |> should.be_true()
}

pub fn is_allowed_by_username_test() {
  telegram.is_allowed(["bob"], "12345|bob") |> should.be_true()
}

pub fn is_allowed_denied_test() {
  telegram.is_allowed(["99999"], "12345|bob") |> should.be_false()
}

pub fn is_allowed_empty_list_test() {
  telegram.is_allowed([], "12345") |> should.be_false()
}

pub fn is_allowed_multiple_entries_test() {
  telegram.is_allowed(["111", "222", "333"], "222|alice")
  |> should.be_true()
}

// --- Telegram group policy tests ---

fn test_telegram_config(group_policy: String) -> TelegramConfig {
  TelegramConfig(
    token: "test-token",
    allow_from: ["*"],
    group_policy: group_policy,
    poll_timeout: 30,
  )
}

pub fn should_process_private_always_test() {
  let config = test_telegram_config("mention")
  telegram.should_process(config, None, "private", "hello", [])
  |> should.be_true()
}

pub fn should_process_group_open_policy_test() {
  let config = test_telegram_config("open")
  telegram.should_process(config, Some("mybot"), "group", "hello", [])
  |> should.be_true()
}

pub fn should_process_group_mention_with_mention_test() {
  let config = test_telegram_config("mention")
  telegram.should_process(
    config,
    Some("mybot"),
    "group",
    "@mybot what time is it?",
    [MessageEntity(entity_type: "mention", offset: 0, length: 6)],
  )
  |> should.be_true()
}

pub fn should_process_group_mention_without_mention_test() {
  let config = test_telegram_config("mention")
  telegram.should_process(config, Some("mybot"), "group", "hello everyone", [])
  |> should.be_false()
}

pub fn should_process_group_mention_no_bot_username_test() {
  let config = test_telegram_config("mention")
  telegram.should_process(config, None, "group", "@mybot hi", [])
  |> should.be_false()
}

pub fn should_process_supergroup_mention_test() {
  let config = test_telegram_config("mention")
  telegram.should_process(
    config,
    Some("mybot"),
    "supergroup",
    "hey @mybot",
    [MessageEntity(entity_type: "mention", offset: 4, length: 6)],
  )
  |> should.be_true()
}

pub fn should_process_group_mention_in_text_test() {
  // Even without entity, if @bot is in text it should match
  let config = test_telegram_config("mention")
  telegram.should_process(
    config,
    Some("mybot"),
    "group",
    "hello @mybot how are you",
    [],
  )
  |> should.be_true()
}

// --- Agent tests with mock provider ---

fn mock_provider(response_content: String) -> provider.Provider {
  Provider(name: "mock", chat: fn(_config, _messages, _tools) {
    Ok(types.LlmResponse(
      content: Some(response_content),
      tool_calls: [],
      stop_reason: types.Stop,
    ))
  })
}

fn mock_provider_with_tool_call() -> provider.Provider {
  let call_count = process.new_subject()

  Provider(name: "mock", chat: fn(_config, messages, _tools) {
    // Check if we already have a tool result in the messages
    let has_tool_result =
      list.any(messages, fn(m) {
        case m {
          types.ToolResultMessage(_, _, _) -> True
          _ -> False
        }
      })
    case has_tool_result {
      True -> {
        process.send(call_count, Nil)
        Ok(types.LlmResponse(
          content: Some("Tool returned: done"),
          tool_calls: [],
          stop_reason: types.Stop,
        ))
      }
      False -> {
        process.send(call_count, Nil)
        Ok(types.LlmResponse(
          content: None,
          tool_calls: [
            types.ToolCall(
              id: "call_1",
              name: "echo",
              arguments: "{\"message\":\"test\"}",
            ),
          ],
          stop_reason: types.ToolUse,
        ))
      }
    }
  })
}

fn mock_agent_config() -> AgentConfig {
  AgentConfig(
    system_prompt: "You are a test bot.",
    model: "test-model",
    max_tokens: 100,
    temperature: None,
    max_iterations: 5,
  )
}

pub fn agent_normal_message_test() {
  let assert Ok(bus_subject) = bus.start()
  let assert Ok(session_store) = session.start()
  let provider = mock_provider("Hello from mock!")
  let tool_list = tools.default_tools()

  let assert Ok(agent_subject) =
    agent.start(mock_agent_config(), provider, tool_list, bus_subject, session_store)

  // Send a message to the agent
  process.send(
    agent_subject,
    agent.ProcessInbound(InboundMessage(
      channel: "test",
      sender_id: "user1",
      chat_id: "chat1",
      content: "hi there",
      metadata: dict.new(),
    )),
  )

  // Consume the outbound response
  let response = bus.consume_outbound(bus_subject)
  response.content |> should.equal("Hello from mock!")
  response.channel |> should.equal("test")
  response.chat_id |> should.equal("chat1")
}

pub fn agent_new_command_test() {
  let assert Ok(bus_subject) = bus.start()
  let assert Ok(session_store) = session.start()
  let provider = mock_provider("unused")
  let tool_list = tools.default_tools()

  let assert Ok(agent_subject) =
    agent.start(mock_agent_config(), provider, tool_list, bus_subject, session_store)

  // First add some history
  session.append_messages(session_store, "test:chat1", [
    types.TextMessage(types.User, "old message"),
  ])

  // Send /new
  process.send(
    agent_subject,
    agent.ProcessInbound(InboundMessage(
      channel: "test",
      sender_id: "user1",
      chat_id: "chat1",
      content: "/new",
      metadata: dict.new(),
    )),
  )

  let response = bus.consume_outbound(bus_subject)
  response.content |> should.equal("New session started.")

  // Verify history was cleared
  let history = session.get_history(session_store, "test:chat1")
  history |> should.equal([])
}

pub fn agent_help_command_test() {
  let assert Ok(bus_subject) = bus.start()
  let assert Ok(session_store) = session.start()
  let provider = mock_provider("unused")
  let tool_list = tools.default_tools()

  let assert Ok(agent_subject) =
    agent.start(mock_agent_config(), provider, tool_list, bus_subject, session_store)

  process.send(
    agent_subject,
    agent.ProcessInbound(InboundMessage(
      channel: "test",
      sender_id: "user1",
      chat_id: "chat1",
      content: "/help",
      metadata: dict.new(),
    )),
  )

  let response = bus.consume_outbound(bus_subject)
  string.contains(response.content, "/new") |> should.be_true()
  string.contains(response.content, "/help") |> should.be_true()
}

pub fn agent_tool_call_loop_test() {
  let assert Ok(bus_subject) = bus.start()
  let assert Ok(session_store) = session.start()
  let provider = mock_provider_with_tool_call()
  let tool_list = tools.default_tools()

  let assert Ok(agent_subject) =
    agent.start(mock_agent_config(), provider, tool_list, bus_subject, session_store)

  process.send(
    agent_subject,
    agent.ProcessInbound(InboundMessage(
      channel: "test",
      sender_id: "user1",
      chat_id: "chat1",
      content: "use a tool",
      metadata: dict.new(),
    )),
  )

  let response = bus.consume_outbound(bus_subject)
  response.content |> should.equal("Tool returned: done")
}

pub fn agent_saves_history_test() {
  let assert Ok(bus_subject) = bus.start()
  let assert Ok(session_store) = session.start()
  let provider = mock_provider("I remember you")
  let tool_list = tools.default_tools()

  let assert Ok(agent_subject) =
    agent.start(mock_agent_config(), provider, tool_list, bus_subject, session_store)

  process.send(
    agent_subject,
    agent.ProcessInbound(InboundMessage(
      channel: "test",
      sender_id: "user1",
      chat_id: "chat1",
      content: "remember this",
      metadata: dict.new(),
    )),
  )

  let _response = bus.consume_outbound(bus_subject)

  // Small delay for async append
  process.sleep(50)

  let history = session.get_history(session_store, "test:chat1")
  case history {
    [types.TextMessage(types.User, user_msg), types.TextMessage(types.Assistant, bot_msg)] -> {
      user_msg |> should.equal("remember this")
      bot_msg |> should.equal("I remember you")
    }
    _ -> should.fail()
  }
}

pub fn agent_provider_error_test() {
  let assert Ok(bus_subject) = bus.start()
  let assert Ok(session_store) = session.start()
  let error_provider =
    Provider(name: "error", chat: fn(_config, _messages, _tools) {
      Error(types.ProviderError(500, "internal error"))
    })
  let tool_list = tools.default_tools()

  let assert Ok(agent_subject) =
    agent.start(mock_agent_config(), error_provider, tool_list, bus_subject, session_store)

  process.send(
    agent_subject,
    agent.ProcessInbound(InboundMessage(
      channel: "test",
      sender_id: "user1",
      chat_id: "chat1",
      content: "hello",
      metadata: dict.new(),
    )),
  )

  let response = bus.consume_outbound(bus_subject)
  string.contains(response.content, "Provider error") |> should.be_true()
}
