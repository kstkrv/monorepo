import envoy
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result

/// Top-level configuration for nanoglaw.
pub type Config {
  Config(
    telegram: TelegramConfig,
    agent: AgentConfig,
    provider: ProviderConfig,
  )
}

/// Telegram channel configuration.
pub type TelegramConfig {
  TelegramConfig(
    token: String,
    /// List of allowed user IDs. Empty list = deny all, ["*"] = allow all.
    allow_from: List(String),
    /// How to handle group messages: "open" or "mention".
    group_policy: String,
    /// Polling timeout in seconds for Telegram getUpdates.
    poll_timeout: Int,
  )
}

/// Agent behaviour configuration.
pub type AgentConfig {
  AgentConfig(
    system_prompt: String,
    model: String,
    max_tokens: Int,
    temperature: Option(Float),
    max_iterations: Int,
  )
}

/// LLM provider configuration.
pub type ProviderConfig {
  ProviderConfig(api_key: String, base_url: String)
}

/// Load configuration from environment variables.
/// All env vars are prefixed with NANOGLAW_.
pub fn from_env() -> Config {
  Config(
    telegram: TelegramConfig(
      token: env_or("NANOGLAW_TELEGRAM_TOKEN", ""),
      allow_from: parse_allow_list(env_or(
        "NANOGLAW_TELEGRAM_ALLOW_FROM",
        "*",
      )),
      group_policy: env_or("NANOGLAW_TELEGRAM_GROUP_POLICY", "mention"),
      poll_timeout: env_or("NANOGLAW_TELEGRAM_POLL_TIMEOUT", "30")
        |> int.parse
        |> result.unwrap(30),
    ),
    agent: AgentConfig(
      system_prompt: env_or(
        "NANOGLAW_SYSTEM_PROMPT",
        default_system_prompt(),
      ),
      model: env_or("NANOGLAW_MODEL", "anthropic/claude-sonnet-4.6"),
      max_tokens: env_or("NANOGLAW_MAX_TOKENS", "8192")
        |> int.parse
        |> result.unwrap(8192),
      temperature: case envoy.get("NANOGLAW_TEMPERATURE") {
        Ok(_) -> Some(0.1)
        Error(_) -> None
      },
      max_iterations: env_or("NANOGLAW_MAX_ITERATIONS", "20")
        |> int.parse
        |> result.unwrap(20),
    ),
    provider: ProviderConfig(
      api_key: env_or("NANOGLAW_API_KEY", ""),
      base_url: env_or("NANOGLAW_API_BASE", "https://openrouter.ai/api/v1"),
    ),
  )
}

fn env_or(key: String, default: String) -> String {
  case envoy.get(key) {
    Ok(val) -> val
    Error(_) -> default
  }
}

fn parse_allow_list(raw: String) -> List(String) {
  case raw {
    "" -> []
    value ->
      value
      |> split_commas
  }
}

@external(erlang, "nanoglaw_ffi", "split_commas")
fn split_commas(input: String) -> List(String)

fn default_system_prompt() -> String {
  "You are nanoglaw, a helpful AI assistant running on the BEAM. "
  <> "Be concise and helpful. You have access to tools for interacting "
  <> "with the environment."
}
