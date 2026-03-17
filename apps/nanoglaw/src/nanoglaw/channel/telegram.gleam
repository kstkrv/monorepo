import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string
import nanoglaw/bus
import nanoglaw/bus/events.{type OutboundMessage, InboundMessage}
import nanoglaw/config.{type TelegramConfig}
import nanoglaw/json_compat

const telegram_api_base = "https://api.telegram.org/bot"

/// Messages the Telegram outbound actor handles.
pub type TelegramMessage {
  /// Send an outbound message via Telegram.
  SendOutbound(OutboundMessage)
  /// Stop the channel.
  Stop
}

type TelegramState {
  TelegramState(config: TelegramConfig)
}

/// Start the Telegram channel: an outbound actor + a polling process.
pub fn start(
  config: TelegramConfig,
  bus_subject: Subject(bus.BusMessage),
) -> Result(Subject(TelegramMessage), Nil) {
  // Start the outbound actor for sending messages
  let state = TelegramState(config:)
  let actor_result =
    actor.new(state)
    |> actor.on_message(handle_outbound)
    |> actor.start

  case actor_result {
    Error(_) -> Error(Nil)
    Ok(started) -> {
      // Start the polling process (linked, so it crashes together)
      start_poll_process(config, bus_subject)
      Ok(started.data)
    }
  }
}

fn handle_outbound(
  state: TelegramState,
  message: TelegramMessage,
) -> actor.Next(TelegramState, TelegramMessage) {
  case message {
    Stop -> actor.stop()
    SendOutbound(msg) -> {
      send_telegram_message(state.config.token, msg.chat_id, msg.content)
      actor.continue(state)
    }
  }
}

// --- Long-polling process ---

/// Start a linked process that long-polls Telegram for updates.
fn start_poll_process(
  config: TelegramConfig,
  bus_subject: Subject(bus.BusMessage),
) -> Nil {
  process.spawn(fn() {
    let bot_info = fetch_bot_info(config.token)
    let bot_username = case bot_info {
      Ok(#(username, _)) -> Some(username)
      Error(_) -> None
    }
    poll_loop(config, bus_subject, 0, bot_username)
  })
  Nil
}

/// Recursive long-poll loop.
fn poll_loop(
  config: TelegramConfig,
  bus_subject: Subject(bus.BusMessage),
  last_update_id: Int,
  bot_username: Option(String),
) -> Nil {
  case fetch_updates(config, last_update_id) {
    Ok(#(updates, new_last_id)) -> {
      list.each(updates, fn(update) {
        process_update(config, bus_subject, update, bot_username)
      })
      poll_loop(config, bus_subject, new_last_id, bot_username)
    }
    Error(_) -> {
      process.sleep(2000)
      poll_loop(config, bus_subject, last_update_id, bot_username)
    }
  }
}

// --- Telegram API ---

fn fetch_bot_info(token: String) -> Result(#(String, Int), Nil) {
  let url = telegram_api_base <> token <> "/getMe"
  let assert Ok(req) = request.to(url)

  case httpc.send(req) {
    Error(_) -> Error(Nil)
    Ok(response) -> {
      let decoder = {
        use result <- decode.field("result", {
          use username <- decode.field("username", decode.string)
          use id <- decode.field("id", decode.int)
          decode.success(#(username, id))
        })
        decode.success(result)
      }
      case json_compat.parse(response.body, decoder) {
        Ok(info) -> Ok(info)
        Error(_) -> Error(Nil)
      }
    }
  }
}

type TelegramUpdate {
  TelegramUpdate(
    update_id: Int,
    chat_id: Int,
    sender_id: Int,
    sender_username: Option(String),
    sender_first_name: Option(String),
    text: String,
    message_id: Int,
    chat_type: String,
    entities: List(MessageEntity),
  )
}

type MessageEntity {
  MessageEntity(entity_type: String, offset: Int, length: Int)
}

fn fetch_updates(
  config: TelegramConfig,
  last_update_id: Int,
) -> Result(#(List(TelegramUpdate), Int), Nil) {
  let offset = case last_update_id {
    0 -> 0
    n -> n + 1
  }
  let url =
    telegram_api_base
    <> config.token
    <> "/getUpdates"

  case request.to(url) {
    Error(_) -> Error(Nil)
    Ok(req) -> {
      let req =
        req
        |> request.set_query([
          #("timeout", int.to_string(config.poll_timeout)),
          #("offset", int.to_string(offset)),
          #("allowed_updates", "[\"message\"]"),
        ])
      case httpc.send(req) {
        Error(_) -> Error(Nil)
        Ok(response) -> parse_updates(response.body)
      }
    }
  }
}

fn parse_updates(body: String) -> Result(#(List(TelegramUpdate), Int), Nil) {
  let entity_decoder = {
    use entity_type <- decode.field("type", decode.string)
    use offset <- decode.field("offset", decode.int)
    use length <- decode.field("length", decode.int)
    decode.success(MessageEntity(entity_type:, offset:, length:))
  }

  let update_decoder = {
    use update_id <- decode.field("update_id", decode.int)
    use message <- decode.field("message", {
      use chat <- decode.field("chat", {
        use chat_id <- decode.field("id", decode.int)
        use chat_type <- decode.optional_field("type", "private", decode.string)
        decode.success(#(chat_id, chat_type))
      })
      use from <- decode.field("from", {
        use sender_id <- decode.field("id", decode.int)
        use username <- decode.optional_field(
          "username",
          None,
          decode.optional(decode.string),
        )
        use first_name <- decode.optional_field(
          "first_name",
          None,
          decode.optional(decode.string),
        )
        decode.success(#(sender_id, username, first_name))
      })
      use text <- decode.optional_field("text", "", decode.string)
      use message_id <- decode.field("message_id", decode.int)
      use entities <- decode.optional_field(
        "entities",
        [],
        decode.list(entity_decoder),
      )
      let #(chat_id, chat_type) = chat
      let #(sender_id, username, first_name) = from
      decode.success(TelegramUpdate(
        update_id:,
        chat_id:,
        sender_id:,
        sender_username: username,
        sender_first_name: first_name,
        text:,
        message_id:,
        chat_type:,
        entities:,
      ))
    })
    decode.success(message)
  }

  let result_decoder = {
    use ok <- decode.field("ok", decode.bool)
    use result <- decode.field("result", decode.list(update_decoder))
    decode.success(#(ok, result))
  }

  case json_compat.parse(body, result_decoder) {
    Error(_) -> Error(Nil)
    Ok(#(True, updates)) -> {
      let last_id = case list.last(updates) {
        Ok(u) -> u.update_id
        Error(_) -> 0
      }
      Ok(#(updates, last_id))
    }
    Ok(#(False, _)) -> Error(Nil)
  }
}

// --- Update processing ---

fn process_update(
  config: TelegramConfig,
  bus_subject: Subject(bus.BusMessage),
  update: TelegramUpdate,
  bot_username: Option(String),
) -> Nil {
  case update.text {
    "" -> Nil
    text -> {
      let sender_id = case update.sender_username {
        Some(username) -> int.to_string(update.sender_id) <> "|" <> username
        None -> int.to_string(update.sender_id)
      }

      case is_allowed(config.allow_from, sender_id) {
        False -> Nil
        True ->
          case
            should_process(
              config,
              bot_username,
              update.chat_type,
              text,
              update.entities,
            )
          {
            False -> Nil
            True -> {
              // Send typing indicator
              send_typing(config.token, int.to_string(update.chat_id))

              // Handle /start and /help locally
              case text {
                "/start" ->
                  send_telegram_message(
                    config.token,
                    int.to_string(update.chat_id),
                    "nanoglaw bot is ready! Send me a message.\n\n/new — New conversation\n/help — Available commands",
                  )
                "/help" ->
                  send_telegram_message(
                    config.token,
                    int.to_string(update.chat_id),
                    "nanoglaw commands:\n/new — Start a new conversation\n/help — Show available commands",
                  )
                _ -> {
                  let metadata =
                    dict.new()
                    |> dict.insert(
                      "message_id",
                      int.to_string(update.message_id),
                    )
                    |> dict.insert("chat_type", update.chat_type)
                    |> maybe_insert("username", update.sender_username)
                    |> maybe_insert("first_name", update.sender_first_name)

                  bus.publish_inbound(
                    bus_subject,
                    InboundMessage(
                      channel: "telegram",
                      sender_id:,
                      chat_id: int.to_string(update.chat_id),
                      content: text,
                      metadata:,
                    ),
                  )
                }
              }
            }
          }
      }
    }
  }
}

fn maybe_insert(
  d: dict.Dict(String, String),
  key: String,
  value: Option(String),
) -> dict.Dict(String, String) {
  case value {
    Some(v) -> dict.insert(d, key, v)
    None -> d
  }
}

fn is_allowed(allow_from: List(String), sender_id: String) -> Bool {
  case allow_from {
    [] -> False
    _ ->
      list.any(allow_from, fn(allowed) {
        allowed == "*"
        || allowed == sender_id
        || {
          case string.split(sender_id, "|") {
            [id, username] -> allowed == id || allowed == username
            _ -> False
          }
        }
      })
  }
}

fn should_process(
  config: TelegramConfig,
  bot_username: Option(String),
  chat_type: String,
  text: String,
  entities: List(MessageEntity),
) -> Bool {
  case chat_type {
    "private" -> True
    _ ->
      case config.group_policy {
        "open" -> True
        _ ->
          case bot_username {
            None -> False
            Some(username) -> {
              let handle = "@" <> username
              let has_mention =
                list.any(entities, fn(e) {
                  case e.entity_type {
                    "mention" -> {
                      let mention =
                        string.slice(text, e.offset, e.length)
                      string.lowercase(mention) == string.lowercase(handle)
                    }
                    _ -> False
                  }
                })
              has_mention
              || string.contains(
                string.lowercase(text),
                string.lowercase(handle),
              )
            }
          }
      }
  }
}

fn send_telegram_message(token: String, chat_id: String, text: String) -> Nil {
  let url = telegram_api_base <> token <> "/sendMessage"
  let body =
    json.object([
      #("chat_id", json.string(chat_id)),
      #("text", json.string(text)),
    ])

  let assert Ok(req) = request.to(url)
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(json.to_string(body))

  case httpc.send(req) {
    Ok(_) -> Nil
    Error(_) -> Nil
  }
}

fn send_typing(token: String, chat_id: String) -> Nil {
  let url = telegram_api_base <> token <> "/sendChatAction"
  let body =
    json.object([
      #("chat_id", json.string(chat_id)),
      #("action", json.string("typing")),
    ])

  let assert Ok(req) = request.to(url)
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(json.to_string(body))

  case httpc.send(req) {
    Ok(_) -> Nil
    Error(_) -> Nil
  }
}
