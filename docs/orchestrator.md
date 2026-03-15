# LLM Agent Orchestrator

## Overview

The orchestrator (`apps/orchestrator/`) is a BEAM-native LLM agent framework. It uses OTP actors to run concurrent agents that can call tools and interact with LLM providers.

## Core Concepts

### Agent

An agent is an OTP actor that runs an agentic loop:

1. Send accumulated messages to an LLM provider
2. Receive response — check stop reason
3. If the LLM requested tool calls, execute them and append results to messages
4. Repeat until the LLM stops or `max_iterations` is reached

Start and interact with agents via the public API:

```gleam
import orchestrator
import orchestrator/provider/openai

let provider = openai.ollama()
let config = types.AgentConfig(
  system_prompt: "You are a helpful assistant.",
  model: "qwen2.5:3b",
  max_tokens: 1024,
  temperature: 0.7,
  max_iterations: 10,
)

let assert Ok(agent) = orchestrator.start_agent(config, provider, tools)
let assert Ok(response) = orchestrator.call(agent, messages, 30_000)
orchestrator.stop(agent)
```

### Provider

A provider is a record wrapping a `chat` function with the signature:

```
(AgentConfig, List(Message), List(Tool)) -> Result(LlmResponse, OrchestratorError)
```

The `openai` module provides an OpenAI-compatible implementation with presets:

| Preset | Function | Base URL |
|--------|----------|----------|
| Custom | `openai.provider(base_url, api_key)` | User-specified |
| OpenRouter | `openai.openrouter(api_key)` | `https://openrouter.ai/api/v1` |
| Ollama (local) | `openai.ollama()` | `http://localhost:11434/v1` |
| Ollama (remote) | `openai.ollama_at(host)` | `http://{host}/v1` |

### Tools

Tools are defined as records:

```gleam
import orchestrator/tool.{Tool}

let add_tool = Tool(
  name: "add",
  description: "Add two numbers",
  parameters: json_schema,  // JSON object describing parameters
  execute: fn(args) { ... },
)
```

The agent automatically executes tool calls from the LLM and feeds results back into the conversation.

## Message Types

- `TextMessage(role, content)` — plain text messages
- `ToolUseMessage(role, content, tool_calls)` — assistant messages requesting tool execution
- `ToolResultMessage(role, content, tool_call_id)` — results returned to the LLM after tool execution

## Error Handling

The `OrchestratorError` type covers:

- `ProviderError(String)` — LLM API returned an error
- `NetworkError(String)` — HTTP request failed
- `DecodeError(String)` — failed to parse LLM response
- `ToolExecutionError(String)` — tool function raised an error
- `MaxIterationsReached` — agent hit the iteration limit
- `Timeout` — actor call timed out

## Adding a New Provider

1. Create a new module under `orchestrator/provider/`
2. Implement a function returning `Provider` — a record with a `chat` field matching the expected signature
3. Handle message encoding, HTTP transport, and response decoding within the `chat` function

## OTP Compatibility

The orchestrator includes an FFI module (`orchestrator_ffi.erl`) that handles JSON library compatibility for OTP versions below 27. Call `orchestrator.init()` before starting agents to ensure proper setup.
