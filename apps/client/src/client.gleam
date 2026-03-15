import lustre
import lustre/attribute
import lustre/element/html

pub fn main() {
  let app =
    lustre.element(
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
      ),
    )
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
