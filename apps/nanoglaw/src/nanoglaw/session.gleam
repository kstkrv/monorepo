import gleam/erlang/process.{type Subject}
import gleam/dict.{type Dict}
import gleam/list
import gleam/otp/actor
import nanoglaw/types.{type Message}

/// A session holds conversation history for a channel:chat_id pair.
pub type Session {
  Session(key: String, messages: List(Message), last_consolidated: Int)
}

/// Messages the session store actor handles.
pub type SessionMessage {
  GetOrCreate(key: String, reply_to: Subject(Session))
  Save(session: Session)
  Clear(key: String)
  AppendMessages(key: String, messages: List(Message))
  GetHistory(key: String, reply_to: Subject(List(Message)))
}

type SessionState {
  SessionState(sessions: Dict(String, Session))
}

/// Start the session store actor. Manages all sessions in-memory via a
/// single actor (could be backed by ETS for higher throughput).
pub fn start() -> Result(Subject(SessionMessage), actor.StartError) {
  let state = SessionState(sessions: dict.new())

  let result =
    actor.new(state)
    |> actor.on_message(handle_message)
    |> actor.start

  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

fn handle_message(
  state: SessionState,
  message: SessionMessage,
) -> actor.Next(SessionState, SessionMessage) {
  case message {
    GetOrCreate(key, reply_to) -> {
      let session = case dict.get(state.sessions, key) {
        Ok(s) -> s
        Error(_) -> Session(key:, messages: [], last_consolidated: 0)
      }
      process.send(reply_to, session)
      let sessions = dict.insert(state.sessions, key, session)
      actor.continue(SessionState(sessions:))
    }

    Save(session) -> {
      let sessions = dict.insert(state.sessions, session.key, session)
      actor.continue(SessionState(sessions:))
    }

    Clear(key) -> {
      let sessions =
        dict.insert(
          state.sessions,
          key,
          Session(key:, messages: [], last_consolidated: 0),
        )
      actor.continue(SessionState(sessions:))
    }

    AppendMessages(key, new_messages) -> {
      let session = case dict.get(state.sessions, key) {
        Ok(s) -> s
        Error(_) -> Session(key:, messages: [], last_consolidated: 0)
      }
      let updated =
        Session(
          ..session,
          messages: list.append(session.messages, new_messages),
        )
      let sessions = dict.insert(state.sessions, key, updated)
      actor.continue(SessionState(sessions:))
    }

    GetHistory(key, reply_to) -> {
      let messages = case dict.get(state.sessions, key) {
        Ok(s) -> s.messages
        Error(_) -> []
      }
      process.send(reply_to, messages)
      actor.continue(state)
    }
  }
}

// --- Convenience helpers ---

/// Get or create a session.
pub fn get_or_create(
  store: Subject(SessionMessage),
  key: String,
) -> Session {
  actor.call(store, 5000, GetOrCreate(key, _))
}

/// Save a session.
pub fn save(store: Subject(SessionMessage), session: Session) -> Nil {
  process.send(store, Save(session))
}

/// Clear a session.
pub fn clear(store: Subject(SessionMessage), key: String) -> Nil {
  process.send(store, Clear(key))
}

/// Append messages to a session.
pub fn append_messages(
  store: Subject(SessionMessage),
  key: String,
  messages: List(Message),
) -> Nil {
  process.send(store, AppendMessages(key, messages))
}

/// Get history for a session.
pub fn get_history(
  store: Subject(SessionMessage),
  key: String,
) -> List(Message) {
  actor.call(store, 5000, GetHistory(key, _))
}
