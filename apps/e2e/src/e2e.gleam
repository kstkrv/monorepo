import gleam/erlang/process
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/string

pub fn main() {
  let base_url = get_env("E2E_BASE_URL", "http://monorepo:8080")

  io.println("E2E: testing " <> base_url)

  // Retry up to 10 times with 3s delay to allow the app to start
  case retry(fn() { check_homepage(base_url) }, 10, 3000) {
    Ok(_) -> {
      io.println("E2E: all checks passed")
      halt(0)
    }
    Error(msg) -> {
      io.println("E2E: FAILED - " <> msg)
      halt(1)
    }
  }
}

fn check_homepage(base_url: String) -> Result(Nil, String) {
  let assert Ok(req) = request.to(base_url <> "/")

  case httpc.send(req) {
    Ok(resp) -> {
      case resp.status {
        200 -> {
          case string.contains(resp.body, "app") {
            True -> {
              io.println("E2E: GET / -> 200 OK, body contains 'app'")
              Ok(Nil)
            }
            False ->
              Error("Response body missing expected content 'app'")
          }
        }
        status ->
          Error(
            "Expected status 200, got " <> int.to_string(status),
          )
      }
    }
    Error(_) -> Error("HTTP request to " <> base_url <> " failed")
  }
}

fn retry(
  f: fn() -> Result(Nil, String),
  attempts: Int,
  delay_ms: Int,
) -> Result(Nil, String) {
  case f() {
    Ok(_) -> Ok(Nil)
    Error(msg) -> {
      case attempts > 1 {
        True -> {
          io.println(
            "E2E: attempt failed ("
            <> msg
            <> "), retrying in "
            <> int.to_string(delay_ms)
            <> "ms... ("
            <> int.to_string(attempts - 1)
            <> " left)",
          )
          process.sleep(delay_ms)
          retry(f, attempts - 1, delay_ms)
        }
        False -> Error(msg)
      }
    }
  }
}

@external(erlang, "e2e_ffi", "get_env")
fn get_env(name: String, default: String) -> String

@external(erlang, "e2e_ffi", "halt")
fn halt(code: Int) -> Nil
