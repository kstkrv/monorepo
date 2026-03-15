import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist.{type Connection, type ResponseData}
import shared

pub fn main() {
  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8080)
    |> mist.bind("0.0.0.0")
    |> mist.start()

  process.sleep_forever()
}

pub fn handler(req: Request(Connection)) -> Response(ResponseData) {
  case shared.route(request.path_segments(req)) {
    shared.ClientJs -> serve_js()
    shared.Html -> serve_html()
  }
}

pub fn serve_html() -> Response(ResponseData) {
  response.new(200)
  |> response.set_header(
    "content-type",
    shared.content_type(shared.Html),
  )
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string(shared.html_template())),
  )
}

pub fn serve_js() -> Response(ResponseData) {
  case read_client_js() {
    Ok(js) ->
      response.new(200)
      |> response.set_header(
        "content-type",
        shared.content_type(shared.ClientJs),
      )
      |> response.set_body(mist.Bytes(bytes_tree.from_string(js)))
    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
  }
}

@external(erlang, "server_ffi", "read_client_js")
pub fn read_client_js() -> Result(String, Nil)
