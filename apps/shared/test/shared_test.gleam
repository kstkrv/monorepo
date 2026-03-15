import gleeunit
import shared

pub fn main() -> Nil {
  gleeunit.main()
}

// --- Route tests ---

pub fn route_client_js_test() {
  let result = shared.route(["client.mjs"])
  assert result == shared.ClientJs
}

pub fn route_root_test() {
  let result = shared.route([])
  assert result == shared.Html
}

pub fn route_unknown_path_test() {
  let result = shared.route(["some", "path"])
  assert result == shared.Html
}

pub fn route_single_segment_test() {
  let result = shared.route(["about"])
  assert result == shared.Html
}

// --- Content type tests ---

pub fn content_type_html_test() {
  let result = shared.content_type(shared.Html)
  assert result == "text/html; charset=utf-8"
}

pub fn content_type_js_test() {
  let result = shared.content_type(shared.ClientJs)
  assert result == "application/javascript"
}

// --- HTML template tests ---

pub fn html_template_is_valid_html_test() {
  let html = shared.html_template()
  assert True == shared.is_html(html)
}

pub fn html_template_has_app_mount_test() {
  let html = shared.html_template()
  assert True == shared.has_app_mount(html)
}

pub fn html_template_has_client_script_test() {
  let html = shared.html_template()
  assert True == shared.has_client_script(html)
}

// --- Validator function tests ---

pub fn is_html_valid_test() {
  assert True == shared.is_html("<!DOCTYPE html><html></html>")
}

pub fn is_html_invalid_test() {
  assert False == shared.is_html("just some text")
}

pub fn is_html_partial_test() {
  assert False == shared.is_html("<!DOCTYPE html> but no closing")
}

pub fn has_app_mount_present_test() {
  assert True == shared.has_app_mount("<div id=\"app\"></div>")
}

pub fn has_app_mount_missing_test() {
  assert False == shared.has_app_mount("<div id=\"root\"></div>")
}

pub fn has_client_script_present_test() {
  assert True == shared.has_client_script("<script src=\"client.mjs\">")
}

pub fn has_client_script_missing_test() {
  assert False == shared.has_client_script("<script src=\"app.js\">")
}
