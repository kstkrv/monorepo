import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist.{type Connection, type ResponseData}

pub fn main() {
  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8080)
    |> mist.bind("0.0.0.0")
    |> mist.start()

  process.sleep_forever()
}

fn handler(req: Request(Connection)) -> Response(ResponseData) {
  case request.path_segments(req) {
    ["client.mjs"] -> serve_js()
    _ -> serve_html()
  }
}

fn serve_html() -> Response(ResponseData) {
  let body =
    "<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>Hello World</title>
</head>
<body>
  <div id=\"app\"></div>
  <script type=\"module\" src=\"/client.mjs\"></script>
</body>
</html>"

  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn serve_js() -> Response(ResponseData) {
  case read_client_js() {
    Ok(js) ->
      response.new(200)
      |> response.set_header("content-type", "application/javascript")
      |> response.set_body(mist.Bytes(bytes_tree.from_string(js)))
    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
  }
}

@external(erlang, "server_ffi", "read_client_js")
fn read_client_js() -> Result(String, Nil)
