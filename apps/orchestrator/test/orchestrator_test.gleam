import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import orchestrator
import orchestrator/provider.{type Provider, Provider}
import orchestrator/provider/openai
import orchestrator/tool.{type Tool, Tool}
import orchestrator/types.{
  type AgentConfig, type LlmResponse, type OrchestratorError, AgentConfig,
  DecodeError, LlmResponse, MaxIterationsReached, Stop, TextMessage, ToolCall,
  ToolUse,
}

pub fn main() {
  orchestrator.init()
  gleeunit.main()
}

// --- Tool tests ---

pub fn tool_execute_known_tool_test() {
  let tools = [
    Tool(
      name: "greet",
      description: "Says hello",
      parameters: json.object([]),
      execute: fn(_args) { Ok("Hello!") },
    ),
  ]

  tool.execute(tools, "greet", "{}")
  |> should.equal(Ok("Hello!"))
}

pub fn tool_execute_unknown_tool_test() {
  tool.execute([], "missing", "{}")
  |> should.equal(Error("Unknown tool: missing"))
}

pub fn tool_execute_failing_tool_test() {
  let tools = [
    Tool(
      name: "fail",
      description: "Always fails",
      parameters: json.object([]),
      execute: fn(_args) { Error("something broke") },
    ),
  ]

  tool.execute(tools, "fail", "{}")
  |> should.equal(Error("something broke"))
}

// --- Response parsing tests ---

pub fn parse_text_response_test() {
  let body =
    "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"

  let assert Ok(response) = openai.parse_response(body)
  response.content |> should.equal(Some("Hello!"))
  response.tool_calls |> should.equal([])
  response.stop_reason |> should.equal(Stop)
}

pub fn parse_tool_call_response_test() {
  let body =
    "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"London\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":15}}"

  let assert Ok(response) = openai.parse_response(body)
  response.content |> should.equal(None)
  response.stop_reason |> should.equal(ToolUse)

  let assert [tc] = response.tool_calls
  tc.id |> should.equal("call_1")
  tc.name |> should.equal("get_weather")
}

pub fn parse_invalid_response_test() {
  let assert Error(DecodeError(_)) = openai.parse_response("{invalid")
}

pub fn parse_empty_choices_test() {
  let body = "{\"choices\":[]}"
  let assert Error(DecodeError(_)) = openai.parse_response(body)
}

// --- Agent actor tests ---

pub fn agent_simple_response_test() {
  let provider =
    mock_provider(fn(_config, _messages, _tools) {
      Ok(LlmResponse(
        content: Some("Hi there!"),
        tool_calls: [],
        stop_reason: Stop,
      ))
    })
  let config = test_config()

  let assert Ok(agent) = orchestrator.start_agent(config, provider, [])
  let result =
    orchestrator.call(agent, [TextMessage(types.User, "Hello")], 5000)

  let assert Ok(response) = result
  response.content |> should.equal(Some("Hi there!"))

  orchestrator.stop(agent)
}

pub fn agent_tool_loop_test() {
  let provider =
    mock_provider(fn(_config, messages, _tools) {
      // If messages contain a tool result, this is the second call
      case has_tool_result(messages) {
        True ->
          Ok(LlmResponse(
            content: Some("The answer is 3."),
            tool_calls: [],
            stop_reason: Stop,
          ))
        False ->
          Ok(LlmResponse(
            content: Some("Let me calculate."),
            tool_calls: [ToolCall("tc_1", "add", "{\"a\": 1, \"b\": 2}")],
            stop_reason: ToolUse,
          ))
      }
    })

  let tools = [
    Tool(
      name: "add",
      description: "Add two numbers",
      parameters: json.object([]),
      execute: fn(_args) { Ok("3") },
    ),
  ]

  let config = test_config()
  let assert Ok(agent) = orchestrator.start_agent(config, provider, tools)
  let result =
    orchestrator.call(
      agent,
      [TextMessage(types.User, "What is 1+2?")],
      5000,
    )

  let assert Ok(response) = result
  response.content |> should.equal(Some("The answer is 3."))

  orchestrator.stop(agent)
}

pub fn agent_max_iterations_test() {
  let provider =
    mock_provider(fn(_config, _messages, _tools) {
      Ok(LlmResponse(
        content: None,
        tool_calls: [ToolCall("tc_1", "loop", "{}")],
        stop_reason: ToolUse,
      ))
    })

  let tools = [
    Tool(
      name: "loop",
      description: "Loops forever",
      parameters: json.object([]),
      execute: fn(_args) { Ok("ok") },
    ),
  ]

  let config =
    AgentConfig(
      system_prompt: "",
      model: "test",
      max_tokens: 100,
      temperature: None,
      max_iterations: 3,
    )

  let assert Ok(agent) = orchestrator.start_agent(config, provider, tools)
  let result =
    orchestrator.call(agent, [TextMessage(types.User, "Loop")], 5000)

  result |> should.equal(Error(MaxIterationsReached))

  orchestrator.stop(agent)
}

// --- Helpers ---

fn test_config() -> AgentConfig {
  AgentConfig(
    system_prompt: "You are helpful.",
    model: "test-model",
    max_tokens: 1024,
    temperature: None,
    max_iterations: 10,
  )
}

fn mock_provider(
  handler: fn(AgentConfig, List(types.Message), List(Tool)) ->
    Result(LlmResponse, OrchestratorError),
) -> Provider {
  Provider(name: "mock", chat: handler)
}

fn has_tool_result(messages: List(types.Message)) -> Bool {
  list.any(messages, fn(msg) {
    case msg {
      types.ToolResultMessage(_, _, _) -> True
      _ -> False
    }
  })
}
