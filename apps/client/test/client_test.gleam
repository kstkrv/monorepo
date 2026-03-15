import gleam/string
import gleeunit
import lustre/attribute
import lustre/element
import lustre/element/html

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn button_renders_with_text_test() {
  let el =
    html.button([], [html.text("It works!")])
  let rendered = element.to_string(el)
  assert True == string.contains(rendered, "It works!")
}

pub fn button_has_green_background_test() {
  let el =
    html.button(
      [attribute.attribute("style", "background-color:#22c55e")],
      [html.text("It works!")],
    )
  let rendered = element.to_string(el)
  assert True == string.contains(rendered, "background-color:#22c55e")
}

pub fn div_renders_with_style_test() {
  let el =
    html.div(
      [attribute.attribute("style", "display:flex;justify-content:center")],
      [],
    )
  let rendered = element.to_string(el)
  assert True == string.contains(rendered, "display:flex")
}

pub fn nested_layout_contains_button_test() {
  let el =
    html.div([], [
      html.button([], [html.text("It works!")]),
    ])
  let rendered = element.to_string(el)
  assert True == string.contains(rendered, "<button>")
  assert True == string.contains(rendered, "It works!")
}
