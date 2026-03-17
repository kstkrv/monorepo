import gleam/dict
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import nanoglaw/bus
import nanoglaw/bus/events.{InboundMessage, OutboundMessage}
import nanoglaw/provider/openai
import nanoglaw/session
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
