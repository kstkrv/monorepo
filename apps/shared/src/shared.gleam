import gleam/string

/// The HTML template for the app shell
pub fn html_template() -> String {
  "<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>Hello World</title>
  <style>body { margin: 0; }</style>
</head>
<body>
  <div id=\"app\"></div>
  <script type=\"module\">import { main } from \"/client.mjs\"; main();</script>
</body>
</html>"
}

/// Determine the route from path segments
pub fn route(segments: List(String)) -> Route {
  case segments {
    ["client.mjs"] -> ClientJs
    _ -> Html
  }
}

pub type Route {
  ClientJs
  Html
}

/// Content type for a given route
pub fn content_type(r: Route) -> String {
  case r {
    ClientJs -> "application/javascript"
    Html -> "text/html; charset=utf-8"
  }
}

/// Check if a string looks like valid HTML
pub fn is_html(text: String) -> Bool {
  string.contains(text, "<!DOCTYPE html>")
  && string.contains(text, "</html>")
}

/// Check if a string contains the app mount point
pub fn has_app_mount(text: String) -> Bool {
  string.contains(text, "<div id=\"app\">")
}

/// Check if the template includes the client script
pub fn has_client_script(text: String) -> Bool {
  string.contains(text, "client.mjs")
}
