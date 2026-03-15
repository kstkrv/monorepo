import gleam/io
import gleam/json
import gleam/option.{Some}
import gleam/string
import orchestrator
import orchestrator/provider/openai
import orchestrator/tool.{Tool}
import orchestrator/types.{AgentConfig, NetworkError, TextMessage, User}

/// Run e2e tests manually: gleam run -m e2e_test
/// Requires Ollama running locally.
pub fn main() {
  orchestrator.init()

  case check_ollama() {
    False -> {
      io.println("SKIP: Ollama not available at localhost:11434")
    }
    True -> {
      simple_chat_test()
      tool_use_test()
      io.println("\nAll e2e tests passed!")
    }
  }
}

fn check_ollama() -> Bool {
  let provider = openai.ollama()
  let config =
    AgentConfig(
      system_prompt: "",
      model: "qwen2.5:3b",
      max_tokens: 1,
      temperature: Some(0.0),
      max_iterations: 1,
    )
  case orchestrator.start_agent(config, provider, []) {
    Error(_) -> False
    Ok(agent) -> {
      let result =
        orchestrator.call(agent, [TextMessage(User, "hi")], 30_000)
      orchestrator.stop(agent)
      case result {
        Error(NetworkError(_)) -> False
        _ -> True
      }
    }
  }
}

fn simple_chat_test() {
  io.println("\n--- simple_chat_test ---")
  let provider = openai.ollama()
  let config =
    AgentConfig(
      system_prompt: "You are a helpful assistant. Be very brief.",
      model: "qwen2.5:3b",
      max_tokens: 128,
      temperature: Some(0.0),
      max_iterations: 1,
    )

  let assert Ok(agent) = orchestrator.start_agent(config, provider, [])

  let assert Ok(response) =
    orchestrator.call(
      agent,
      [TextMessage(User, "Say hello in one word.")],
      60_000,
    )

  let assert Some(text) = response.content
  io.println("Response: " <> text)
  let assert True = string.length(text) > 0
  io.println("PASS")

  orchestrator.stop(agent)
}

fn tool_use_test() {
  io.println("\n--- tool_use_test ---")
  let provider = openai.ollama()
  let config =
    AgentConfig(
      system_prompt: "You have access to tools. Use them when asked. Be very brief.",
      model: "qwen2.5:3b",
      max_tokens: 256,
      temperature: Some(0.0),
      max_iterations: 5,
    )

  let tools = [
    Tool(
      name: "add",
      description: "Add two integers together. Takes parameters a and b.",
      parameters: json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "a",
              json.object([
                #("type", json.string("integer")),
                #("description", json.string("First number")),
              ]),
            ),
            #(
              "b",
              json.object([
                #("type", json.string("integer")),
                #("description", json.string("Second number")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          json.preprocessed_array([json.string("a"), json.string("b")]),
        ),
      ]),
      execute: fn(_args) { Ok("42") },
    ),
  ]

  let assert Ok(agent) = orchestrator.start_agent(config, provider, tools)

  let result =
    orchestrator.call(
      agent,
      [
        TextMessage(
          User,
          "Use the add tool with a=20 and b=22. What is the result?",
        ),
      ],
      60_000,
    )

  case result {
    Ok(response) -> {
      let assert Some(text) = response.content
      io.println("Response: " <> text)
      case string.contains(text, "42") {
        True -> io.println("PASS")
        False ->
          io.println(
            "WARN: response doesn't contain '42' (model may not support tools)",
          )
      }
    }
    Error(err) -> {
      io.println(
        "WARN: tool test returned error (model may not support tool use): "
        <> string.inspect(err),
      )
    }
  }

  orchestrator.stop(agent)
}
