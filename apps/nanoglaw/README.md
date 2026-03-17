# nanoglaw

A BEAM-native LLM agent bot written in [Gleam](https://gleam.run), with Telegram integration. Think of it as [nanobot](https://github.com/HKUDS/nanobot) rebuilt from scratch to leverage OTP actors, message passing, and the Erlang runtime.

nanoglaw runs an agentic loop — it calls an LLM, executes any requested tools, feeds the results back, and repeats until the model is done — all coordinated through a tree of OTP actors.

## Architecture

```
                         ┌──────────────────────┐
                         │     nanoglaw.main     │
                         │   (startup + wiring)  │
                         └──────────┬─────────────┘
                                    │ starts
            ┌───────────────────────┼────────────────────────┐
            ▼                       ▼                        ▼
   ┌─────────────────┐   ┌──────────────────┐    ┌────────────────────┐
   │   Message Bus    │   │  Session Store   │    │  Channel Manager   │
   │   (OTP actor)    │   │  (OTP actor)     │    │   (OTP actor)      │
   │                  │   │                  │    │                    │
   │ inbound queue ←──┼───┼──────────────────┼────┤── Telegram poller  │
   │ outbound queue ──┼───┼──────────────────┼───►│   (linked process) │
   │ waiter lists     │   │  Dict(key,       │    │                    │
   │                  │   │    Session)       │    │── Telegram sender  │
   └────────┬─────────┘   └──────────────────┘    │   (OTP actor)      │
            │                                     └────────────────────┘
            │ consume_inbound
            ▼
   ┌─────────────────┐
   │   Agent Actor    │
   │                  │
   │ LLM call ──►     │
   │ tool exec ──►    │
   │ loop until done  │
   │                  │
   │ publish_outbound │
   └─────────────────┘
```

### Actor tree

Every box above is an OTP actor (or a linked process). They communicate exclusively via typed message passing — no shared mutable state, no locks, no callbacks.

| Actor / Process | Module | Role |
|---|---|---|
| **Message Bus** | `nanoglaw/bus` | Dual-queue broker with waiter pattern. Decouples channels from the agent. |
| **Session Store** | `nanoglaw/session` | In-memory conversation history keyed by `channel:chat_id`. |
| **Agent** | `nanoglaw/agent` | Receives inbound messages, runs the agentic loop, publishes responses. |
| **Channel Manager** | `nanoglaw/channel/manager` | Starts channel actors, routes outbound messages to the correct channel. |
| **Telegram Sender** | `nanoglaw/channel/telegram` | OTP actor that sends messages via the Telegram Bot API. |
| **Telegram Poller** | `nanoglaw/channel/telegram` | Linked process that long-polls `getUpdates` and publishes to the bus. |
| **Inbound Dispatcher** | `nanoglaw` (main) | Spawned process that loops `consume_inbound` → `agent.ProcessInbound`. |
| **Outbound Dispatcher** | `nanoglaw/channel/manager` | Spawned process that loops `consume_outbound` → `manager.DispatchOutbound`. |

### Message flow

1. **Telegram poller** receives an update via long-polling → publishes `InboundMessage` to the **bus**
2. **Inbound dispatcher** consumes from the bus → sends `ProcessInbound` to the **agent**
3. **Agent** loads session history, appends the user message, and enters the **agentic loop**:
   - Calls the LLM provider with the full message list + available tools
   - If the LLM requests tool calls → executes them, appends results, and loops
   - If the LLM returns a final response (stop reason = `Stop`) → exits the loop
   - Safety valve: stops after `max_iterations` to prevent runaway loops
4. **Agent** saves the conversation turn to the **session store** and publishes `OutboundMessage` to the **bus**
5. **Outbound dispatcher** consumes from the bus → sends `DispatchOutbound` to the **channel manager**
6. **Channel manager** routes to **Telegram sender** → HTTP POST to `sendMessage`

## Module reference

### Core types

**`nanoglaw/types`** — Shared types used across all modules:
- `Role` — `System | User | Assistant | Tool`
- `Message` — `TextMessage(role, content) | ToolUseMessage(id, name, arguments) | ToolResultMessage(tool_use_id, content, is_error)`
- `ToolCall` — `ToolCall(id, name, arguments)` — a tool invocation requested by the LLM
- `LlmResponse` — `LlmResponse(content: Option(String), tool_calls: List(ToolCall), stop_reason: StopReason)`
- `StopReason` — `Stop | ToolUse | MaxTokens`
- `NanoglawError` — unified error type: `ProviderError | NetworkError | DecodeError | ToolExecutionError | MaxIterationsReached | Timeout | ConfigError | TelegramError`

### Message bus

**`nanoglaw/bus`** — The central message broker, implemented as an OTP actor.

Maintains two independent queues (inbound and outbound), each with a **waiter list**. When a consumer calls `consume_inbound` and the queue is empty, its reply subject is parked in the waiter list. When a publisher calls `publish_inbound`, the message is delivered directly to a waiting consumer if one exists — otherwise it's enqueued. This gives efficient backpressure without polling.

```gleam
// Non-blocking publish
bus.publish_inbound(bus_subject, msg)

// Blocking consume (with timeout in ms)
let assert Ok(msg) = bus.consume_inbound(bus_subject, 5000)
```

**`nanoglaw/bus/events`** — Event types:
- `InboundMessage(channel, sender_id, chat_id, content, metadata)` — from a channel
- `OutboundMessage(channel, chat_id, content, metadata)` — to a channel
- `session_key(msg)` — derives `"channel:chat_id"` for session lookup

### Session management

**`nanoglaw/session`** — In-memory conversation store as an OTP actor. Each session is keyed by `"channel:chat_id"` (e.g., `"telegram:123456"`).

Operations:
- `get_or_create(store, key)` — returns the session, creating it if needed (synchronous via `actor.call`)
- `append_messages(store, key, messages)` — appends messages to history (async fire-and-forget)
- `get_history(store, key)` — returns the full message list (synchronous)
- `clear(store, key)` — resets the session to empty (async)

All reads are synchronous (using `actor.call` with a 5s timeout) to ensure consistency. Writes are async (using `process.send`) since they don't need a response.

### Agent

**`nanoglaw/agent`** — The agentic loop actor. Handles two messages:
- `ProcessInbound(msg)` — runs the full loop for one user message
- `Shutdown` — stops the actor

Built-in command handling:
- `/new` — clears the session and confirms
- `/help` — returns available commands

The agentic loop (`run_loop`) is recursive:
1. Check iteration count against `max_iterations`
2. Call `provider.chat(config, messages, tools)`
3. If `stop_reason == ToolUse` → execute all tool calls, append results, recurse
4. If `stop_reason == Stop` → return the response
5. On error → return the error (formatted for the user)

### Provider

**`nanoglaw/provider`** — Provider abstraction using a record-of-functions pattern:

```gleam
pub type Provider {
  Provider(
    name: String,
    chat: fn(AgentConfig, List(Message), List(Tool)) ->
      Result(LlmResponse, NanoglawError),
  )
}
```

This makes providers swappable at runtime without needing Gleam behaviours or traits.

**`nanoglaw/provider/openai`** — OpenAI-compatible implementation. Works with any API that follows the OpenAI chat completions format.

Built-in presets:
```gleam
// OpenRouter (default)
openai.provider(api_key, "https://openrouter.ai/api/v1")

// OpenRouter shorthand
openai.openrouter(api_key)

// Local Ollama
openai.ollama()

// Ollama at custom host
openai.ollama_at("http://192.168.1.100:11434")
```

Handles full request encoding (messages, tools, system prompt, temperature) and response decoding (content, tool calls, finish reasons).

### Tools

**`nanoglaw/tool`** — Tool type definition and registry:
```gleam
pub type Tool {
  Tool(
    name: String,
    description: String,
    parameters: Json,           // JSON Schema
    execute: fn(String) -> Result(String, String),  // raw JSON in, string out
  )
}
```

`tool.execute(tools, name, arguments)` looks up and runs a tool by name.

**`nanoglaw/agent/tools`** — Default tool implementations:
- **`echo`** — Echoes back the input message. Useful for testing.
- **`current_time`** — Returns the current UTC time in ISO 8601 format (via Erlang FFI).

### Telegram channel

**`nanoglaw/channel/telegram`** — Direct integration with the Telegram Bot API via HTTP. No external Telegram library — just `gleam_httpc` requests.

Two components:
1. **Sender actor** — receives `SendOutbound(msg)`, calls `sendMessage`. Also handles `Stop`.
2. **Poller process** — linked to the sender. Calls `getMe` on startup (to learn the bot's username for @mention detection), then enters a recursive long-poll loop calling `getUpdates`.

Features:
- **Allowlist** (`NANOGLAW_TELEGRAM_ALLOW_FROM`) — restricts who can interact. Matches against user ID, username, or `id|username` compound format. `*` allows everyone.
- **Group policy** (`NANOGLAW_TELEGRAM_GROUP_POLICY`) — `"mention"` (default) requires @bot mention in groups; `"open"` processes all group messages.
- **Typing indicator** — sends `sendChatAction(typing)` before processing.
- **Local commands** — `/start` and `/help` are handled directly in the channel without hitting the agent.

### Channel manager

**`nanoglaw/channel/manager`** — Manages channel lifecycle and outbound routing.

- `StartChannels` — initializes Telegram if the token is configured
- `DispatchOutbound(msg)` — routes by `msg.channel` to the correct sender actor
- `StopAll` — shuts down all channels

### Configuration

**`nanoglaw/config`** — Loads all configuration from `NANOGLAW_*` environment variables.

### JSON compatibility

**`nanoglaw/json_compat`** — Wraps [thoas](https://hex.pm/packages/thoas) for JSON decoding. This exists because `gleam_json` v3's `json.parse()` requires OTP 27+, but nanoglaw targets OTP 25+. The wrapper calls `thoas:decode/1` via Erlang FFI, then pipes the result through Gleam's `decode.run()`.

### Erlang FFI

**`nanoglaw_ffi.erl`** — Two helper functions:
- `split_commas/1` — splits a comma-separated string into a list of trimmed binaries
- `current_iso_time/0` — returns the current UTC time as an ISO 8601 binary

## Configuration

All configuration is via environment variables:

| Variable | Default | Description |
|---|---|---|
| `NANOGLAW_API_KEY` | *(required)* | API key for the LLM provider |
| `NANOGLAW_API_BASE` | `https://openrouter.ai/api/v1` | Base URL for the OpenAI-compatible API |
| `NANOGLAW_MODEL` | `anthropic/claude-sonnet-4-20250514` | Model identifier |
| `NANOGLAW_SYSTEM_PROMPT` | Built-in default | System prompt for the agent |
| `NANOGLAW_MAX_TOKENS` | `8192` | Maximum tokens in LLM response |
| `NANOGLAW_MAX_ITERATIONS` | `20` | Maximum agentic loop iterations per message |
| `NANOGLAW_TEMPERATURE` | *(unset = provider default)* | If set (to any value), uses temperature 0.1 |
| `NANOGLAW_TELEGRAM_TOKEN` | *(empty = disabled)* | Telegram Bot API token from @BotFather |
| `NANOGLAW_TELEGRAM_ALLOW_FROM` | `*` | Comma-separated list of allowed user IDs/usernames, or `*` for all |
| `NANOGLAW_TELEGRAM_GROUP_POLICY` | `mention` | `mention` (require @bot) or `open` (process all group messages) |
| `NANOGLAW_TELEGRAM_POLL_TIMEOUT` | `30` | Long-poll timeout in seconds for `getUpdates` |

## Build and run

```sh
cd apps/nanoglaw

# Build
gleam build

# Run tests
gleam test

# Run the bot
NANOGLAW_API_KEY=your-key NANOGLAW_TELEGRAM_TOKEN=your-token gleam run
```

### Quick start with OpenRouter

1. Get an API key from [openrouter.ai](https://openrouter.ai)
2. Create a Telegram bot via [@BotFather](https://t.me/BotFather)
3. Run:
```sh
export NANOGLAW_API_KEY="sk-or-..."
export NANOGLAW_TELEGRAM_TOKEN="123456:ABC..."
cd apps/nanoglaw && gleam run
```

### Using with Ollama (local models)

```sh
export NANOGLAW_API_KEY="ollama"
export NANOGLAW_API_BASE="http://localhost:11434/v1"
export NANOGLAW_MODEL="llama3.1"
export NANOGLAW_TELEGRAM_TOKEN="123456:ABC..."
cd apps/nanoglaw && gleam run
```

## Tests

```sh
cd apps/nanoglaw && gleam test
```

The test suite covers:
- **Bus** — publish/consume for both inbound and outbound queues
- **Session** — get_or_create, append + history retrieval, clear
- **Events** — session key derivation from inbound messages
- **Provider** — OpenAI response parsing for text responses and tool call responses

All tests are pure and fast — no network calls, no external dependencies.

## Adding a new tool

1. Create a function that returns a `Tool` in `src/nanoglaw/agent/tools.gleam`:

```gleam
fn my_tool() -> Tool {
  Tool(
    name: "my_tool",
    description: "What this tool does (shown to the LLM).",
    parameters: json.object([
      #("type", json.string("object")),
      #("properties", json.object([
        #("input", json.object([
          #("type", json.string("string")),
          #("description", json.string("The input parameter")),
        ])),
      ])),
      #("required", json.preprocessed_array([json.string("input")])),
    ]),
    execute: fn(arguments) {
      let decoder = {
        use input <- decode.field("input", decode.string)
        decode.success(input)
      }
      case json_compat.parse(arguments, decoder) {
        Ok(input) -> Ok("Result: " <> input)
        Error(_) -> Error("Failed to parse arguments")
      }
    },
  )
}
```

2. Add it to the `default_tools()` list:

```gleam
pub fn default_tools() -> List(Tool) {
  [echo_tool(), current_time_tool(), my_tool()]
}
```

That's it. The agent will automatically include the tool in LLM requests and execute it when called.

## Design decisions

### Why direct HTTP instead of a Telegram library?

The `telega` Gleam library (v0.15.0) causes a compiler segfault with Gleam 1.14.0. Rather than pin to an older compiler or wait for a fix, nanoglaw implements Telegram integration directly via `gleam_httpc` — it's ~200 lines of straightforward HTTP calls and JSON decoding, giving full control over polling behaviour and error handling.

### Why `json_compat` instead of `gleam_json`'s parser?

`gleam_json` v3's `json.parse()` calls `gleam_json_ffi:decode`, which uses the Erlang `json` module — only available in OTP 27+. Since this project targets OTP 25+, nanoglaw uses a thin wrapper around [thoas](https://hex.pm/packages/thoas) (a pure-Erlang JSON library already pulled in by `gleam_json` for encoding). Encoding still goes through `gleam_json` as normal.

### Why a message bus instead of direct actor messaging?

The bus decouples channels from the agent. Channels don't need to know about the agent, and the agent doesn't need to know about channels. This makes it trivial to add new channels — just publish `InboundMessage` to the bus and subscribe to `OutboundMessage`. The waiter pattern inside the bus gives efficient blocking consumption without polling.

### Why record-of-functions for providers?

Gleam doesn't have traits or interfaces. The record-of-functions pattern (`Provider(name, chat: fn(...) -> ...)`) gives runtime polymorphism — you can swap providers by passing a different record. This is idiomatic Gleam and mirrors how the broader ecosystem handles similar problems.

## Comparison with nanobot (Python)

| Concept | nanobot (Python) | nanoglaw (Gleam/BEAM) |
|---|---|---|
| Concurrency | asyncio event loop | OTP actors + message passing |
| State management | In-memory dicts | Actor-encapsulated state |
| Channel abstraction | Abstract base class | Message bus + typed events |
| Provider abstraction | Protocol/ABC | Record-of-functions |
| Tool definition | Pydantic models | Gleam records + JSON Schema |
| Error handling | Exceptions | Result types |
| Session storage | Dict | OTP actor with Dict |
| Configuration | pydantic-settings | Environment variables via envoy |
| Telegram integration | python-telegram-bot | Direct HTTP (gleam_httpc) |

## Dependencies

| Package | Purpose |
|---|---|
| `gleam_stdlib` | Standard library |
| `gleam_otp` | OTP actor framework |
| `gleam_erlang` | Erlang interop (process, subject) |
| `gleam_http` | HTTP types |
| `gleam_httpc` | HTTP client |
| `gleam_json` | JSON encoding |
| `thoas` | JSON decoding (OTP 25+ compatible) |
| `envoy` | Environment variable access |
| `simplifile` | File system access |
| `gleeunit` | Test framework (dev) |
