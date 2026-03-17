import gleam/dynamic/decode.{type Decoder}
import gleam/json

/// Parse a JSON string using gleam_json (requires OTP 27+).
pub fn parse(
  from json_string: String,
  using decoder: Decoder(t),
) -> Result(t, Nil) {
  case json.parse(json_string, decoder) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}
