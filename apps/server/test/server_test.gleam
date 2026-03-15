import gleam/bit_array
import gleam/bytes_tree
import gleeunit
import mist
import server
import shared

pub fn main() -> Nil {
  gleeunit.main()
}

// --- serve_html tests ---

pub fn serve_html_status_test() {
  let resp = server.serve_html()
  assert resp.status == 200
}

pub fn serve_html_content_type_test() {
  let resp = server.serve_html()
  let expected = shared.content_type(shared.Html)
  let assert Ok(ct) = find_header(resp.headers, "content-type")
  assert ct == expected
}

pub fn serve_html_body_is_valid_html_test() {
  let resp = server.serve_html()
  let body_str = response_body_to_string(resp.body)
  assert True == shared.is_html(body_str)
}

pub fn serve_html_body_has_app_mount_test() {
  let resp = server.serve_html()
  let body_str = response_body_to_string(resp.body)
  assert True == shared.has_app_mount(body_str)
}

pub fn serve_html_body_has_client_script_test() {
  let resp = server.serve_html()
  let body_str = response_body_to_string(resp.body)
  assert True == shared.has_client_script(body_str)
}

// --- serve_js tests ---

pub fn serve_js_returns_valid_status_test() {
  let resp = server.serve_js()
  assert resp.status == 200 || resp.status == 404
}

pub fn serve_js_content_type_when_found_test() {
  let resp = server.serve_js()
  case resp.status {
    200 -> {
      let assert Ok(ct) = find_header(resp.headers, "content-type")
      assert ct == "application/javascript"
    }
    _ -> Nil
  }
}

// --- read_client_js tests ---

pub fn read_client_js_returns_result_test() {
  let result = server.read_client_js()
  case result {
    Ok(js) -> {
      let not_empty = js != ""
      assert True == not_empty
    }
    Error(Nil) -> Nil
  }
}

// --- Helpers ---

fn find_header(
  headers: List(#(String, String)),
  name: String,
) -> Result(String, Nil) {
  case headers {
    [] -> Error(Nil)
    [#(key, value), ..] if key == name -> Ok(value)
    [_, ..rest] -> find_header(rest, name)
  }
}

fn response_body_to_string(body: mist.ResponseData) -> String {
  let assert mist.Bytes(tree) = body
  let bits = bytes_tree.to_bit_array(tree)
  let assert Ok(str) = bit_array.to_string(bits)
  str
}
