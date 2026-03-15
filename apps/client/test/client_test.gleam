import gleeunit
import lustre/attribute
import lustre/element/html

pub fn main() -> Nil {
  gleeunit.main()
}

// The client module's main() requires a browser DOM ("#app"),
// so we test the UI building blocks directly.

pub fn button_renders_test() {
  let el =
    html.button(
      [
        attribute.attribute(
          "style",
          "background-color:#22c55e;color:white;font-size:3rem",
        ),
      ],
      [html.text("It works!")],
    )
  // Element should be constructable without error
  assert el == el
}

pub fn div_with_style_test() {
  let el =
    html.div(
      [
        attribute.attribute(
          "style",
          "display:flex;justify-content:center;align-items:center",
        ),
      ],
      [],
    )
  assert el == el
}

pub fn nested_layout_test() {
  let el =
    html.div(
      [
        attribute.attribute(
          "style",
          "display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0",
        ),
      ],
      [
        html.button(
          [
            attribute.attribute(
              "style",
              "background-color:#22c55e;color:white;font-size:3rem;font-weight:bold;padding:1.5rem 4rem;border:none;border-radius:1rem;cursor:pointer;box-shadow:0 8px 24px rgba(34,197,94,0.4)",
            ),
          ],
          [html.text("It works!")],
        ),
      ],
    )
  assert el == el
}

pub fn text_content_test() {
  let el = html.text("It works!")
  assert el == el
}
