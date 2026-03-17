import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import nanoglaw/bus/events.{type InboundMessage, type OutboundMessage}

/// Messages the bus actor handles.
pub type BusMessage {
  /// A channel publishes an inbound message.
  PublishInbound(InboundMessage)
  /// The agent publishes an outbound message.
  PublishOutbound(OutboundMessage)
  /// The agent consumes the next inbound message (blocks via reply).
  ConsumeInbound(reply_to: Subject(InboundMessage))
  /// A channel consumes the next outbound message (blocks via reply).
  ConsumeOutbound(reply_to: Subject(OutboundMessage))
}

/// Internal queue state.
type BusState {
  BusState(
    inbound: List(InboundMessage),
    outbound: List(OutboundMessage),
    inbound_waiters: List(Subject(InboundMessage)),
    outbound_waiters: List(Subject(OutboundMessage)),
  )
}

/// Start the message bus actor.
pub fn start() -> Result(Subject(BusMessage), actor.StartError) {
  let state =
    BusState(
      inbound: [],
      outbound: [],
      inbound_waiters: [],
      outbound_waiters: [],
    )

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
  state: BusState,
  message: BusMessage,
) -> actor.Next(BusState, BusMessage) {
  case message {
    PublishInbound(msg) -> {
      case state.inbound_waiters {
        // Someone is waiting — deliver directly.
        [waiter, ..rest] -> {
          process.send(waiter, msg)
          actor.continue(BusState(..state, inbound_waiters: rest))
        }
        // No one waiting — enqueue.
        [] ->
          actor.continue(
            BusState(..state, inbound: list_append(state.inbound, msg)),
          )
      }
    }

    PublishOutbound(msg) -> {
      case state.outbound_waiters {
        [waiter, ..rest] -> {
          process.send(waiter, msg)
          actor.continue(BusState(..state, outbound_waiters: rest))
        }
        [] ->
          actor.continue(
            BusState(..state, outbound: list_append(state.outbound, msg)),
          )
      }
    }

    ConsumeInbound(reply_to) -> {
      case state.inbound {
        [msg, ..rest] -> {
          process.send(reply_to, msg)
          actor.continue(BusState(..state, inbound: rest))
        }
        [] ->
          actor.continue(
            BusState(
              ..state,
              inbound_waiters: list_append(state.inbound_waiters, reply_to),
            ),
          )
      }
    }

    ConsumeOutbound(reply_to) -> {
      case state.outbound {
        [msg, ..rest] -> {
          process.send(reply_to, msg)
          actor.continue(BusState(..state, outbound: rest))
        }
        [] ->
          actor.continue(
            BusState(
              ..state,
              outbound_waiters: list_append(state.outbound_waiters, reply_to),
            ),
          )
      }
    }
  }
}

/// Append to end of list (queue semantics).
fn list_append(list: List(a), item: a) -> List(a) {
  case list {
    [] -> [item]
    [head, ..tail] -> [head, ..list_append(tail, item)]
  }
}

// --- Convenience helpers ---

/// Publish an inbound message to the bus (non-blocking).
pub fn publish_inbound(bus: Subject(BusMessage), msg: InboundMessage) -> Nil {
  process.send(bus, PublishInbound(msg))
}

/// Publish an outbound message to the bus (non-blocking).
pub fn publish_outbound(bus: Subject(BusMessage), msg: OutboundMessage) -> Nil {
  process.send(bus, PublishOutbound(msg))
}

/// Consume the next inbound message (blocks forever until one is available).
pub fn consume_inbound(
  bus: Subject(BusMessage),
) -> InboundMessage {
  process.call_forever(bus, ConsumeInbound)
}

/// Consume the next outbound message (blocks forever until one is available).
pub fn consume_outbound(
  bus: Subject(BusMessage),
) -> OutboundMessage {
  process.call_forever(bus, ConsumeOutbound)
}
