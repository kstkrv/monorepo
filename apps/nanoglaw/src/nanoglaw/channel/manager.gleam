import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import nanoglaw/bus
import nanoglaw/bus/events.{type OutboundMessage}
import nanoglaw/channel/telegram
import nanoglaw/config.{type Config}

/// Messages the channel manager handles.
pub type ManagerMessage {
  /// Start all configured channels.
  StartChannels
  /// Dispatch an outbound message to the right channel.
  DispatchOutbound(OutboundMessage)
  /// Stop all channels.
  StopAll
}

type ManagerState {
  ManagerState(
    config: Config,
    bus: Subject(bus.BusMessage),
    telegram: Result(Subject(telegram.TelegramMessage), Nil),
  )
}

/// Start the channel manager actor.
pub fn start(
  config: Config,
  bus_subject: Subject(bus.BusMessage),
) -> Result(Subject(ManagerMessage), actor.StartError) {
  let state = ManagerState(config:, bus: bus_subject, telegram: Error(Nil))

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
  state: ManagerState,
  message: ManagerMessage,
) -> actor.Next(ManagerState, ManagerMessage) {
  case message {
    StartChannels -> {
      // Start Telegram if token is configured
      let tg_result = case state.config.telegram.token {
        "" -> Error(Nil)
        _ -> telegram.start(state.config.telegram, state.bus)
      }
      actor.continue(ManagerState(..state, telegram: tg_result))
    }

    DispatchOutbound(msg) -> {
      case msg.channel {
        "telegram" ->
          case state.telegram {
            Ok(tg) -> process.send(tg, telegram.SendOutbound(msg))
            Error(_) -> Nil
          }
        _ -> Nil
      }
      actor.continue(state)
    }

    StopAll -> {
      case state.telegram {
        Ok(tg) -> process.send(tg, telegram.Stop)
        Error(_) -> Nil
      }
      actor.stop()
    }
  }
}

/// Start the outbound dispatch loop. Consumes outbound messages from the
/// bus and forwards them to the channel manager for delivery.
pub fn start_outbound_dispatcher(
  bus_subject: Subject(bus.BusMessage),
  manager: Subject(ManagerMessage),
) -> Nil {
  process.spawn(fn() { dispatch_loop(bus_subject, manager) })
  Nil
}

fn dispatch_loop(
  bus_subject: Subject(bus.BusMessage),
  manager: Subject(ManagerMessage),
) -> Nil {
  let msg = bus.consume_outbound(bus_subject)
  process.send(manager, DispatchOutbound(msg))
  dispatch_loop(bus_subject, manager)
}
