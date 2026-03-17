import gleam/dict.{type Dict}

/// Message received from a channel (e.g. Telegram).
pub type InboundMessage {
  InboundMessage(
    channel: String,
    sender_id: String,
    chat_id: String,
    content: String,
    /// Optional metadata from the channel (message_id, username, etc.).
    metadata: Dict(String, String),
  )
}

/// Message to send back through a channel.
pub type OutboundMessage {
  OutboundMessage(
    channel: String,
    chat_id: String,
    content: String,
    /// Optional metadata for the channel (reply_to_message_id, etc.).
    metadata: Dict(String, String),
  )
}

/// Derive a session key from an inbound message.
pub fn session_key(msg: InboundMessage) -> String {
  msg.channel <> ":" <> msg.chat_id
}

/// Create an empty metadata dict.
pub fn new_metadata() -> Dict(String, String) {
  dict.new()
}
