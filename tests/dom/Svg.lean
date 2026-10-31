import LitheTest.Util

open Lithe LitheTest
open Js.Dom
open Std.Async

/-! Checks that SVG ends up in the right namespace, however it reaches the page. -/

structure Model where
  radius : Nat := 1
  width : Option Nat := some 10
  clicks : Nat := 0
  targetTag : String := ""
  deriving Inhabited

abbrev Up := Model → Model

def clicked (e : Lithe.Event) : Up := fun m => { m with clicks := m.clicks + 1, targetTag := e.targetTag }

def grow : Up := fun m => { m with radius := m.radius + 1, width := none }

/-- An SVG element at the root of its own markup. -/
def bar (m : Model) : Html Up :=
  <rect id="fragment" x="1" width={m.width} onclick={clicked}><title>{toString m.radius}</title></rect>

/-- SVG elements that are built at run time. -/
def built : Html Up :=
  .elem "g" #[.value "id" (.str "built")] #[
    .elem "circle" #[] #[],
    .elem "foreignObject" #[] #[.elem "div" #[.value "id" (.str "built-html")] #[]]]

def view (m : Model) : Html Up :=
  <main id="page" data-clicks={m.clicks} data-target={m.targetTag}>
    <svg id="chart" viewBox="0 0 10 10" preserveAspectRatio={"none"} class={#["a", cls "b" (m.radius > 1)]}>
      <linearGradient id="gradient" gradientUnits={"userSpaceOnUse"} />
      <circle id="dot" r={m.radius} stroke-width={m.radius} onclick={grow} />
      {bar m}
      {built}
      {Html.forEach #[1, 2] id fun n => <use id={s!"use-{n}"} href="#dot" />}
      <text id="label">{toString m.radius}</text>
      <foreignObject>
        <div id="html"><input id="input" value={toString m.radius} /></div>
        {(<p id="hole-html">a</p>)}
      </foreignObject>
    </svg>
    {Html.elem "svg" #[.value "id" (.str "built-root")] #[.elem "circle" #[] #[]]}
    {Html.elem "div" #[.value "id" (.str "built-outside")] #[]}
  </main>

def svgNamespace : String := "http://www.w3.org/2000/svg"
def htmlNamespace : String := "http://www.w3.org/1999/xhtml"

/-- Returns the first element in `root` that matches `selector`, which needn't be an HTML element. -/
def findAny (root : Element) (selector : String) : IO Element := do
  let some e ← root.querySelector selector | throw (.userError s!"no match for {selector}")
  return e

/-- Returns the namespace of the first match for `selector` in `root`. -/
def namespaceOf (root : Element) (selector : String) : IO String := do
  fromJs (← (← findAny root selector).val.get "namespaceURI")

def run : Async Unit := do
  let root ← newRoot
  (App.simple ({} : Model) view).mount root

  for selector in ["#chart", "#gradient", "#dot", "#fragment", "#fragment title", "#built", "#built circle",
      "#built foreignObject", "#use-1", "#label", "foreignObject", "#built-root", "#built-root circle"] do
    checkEq s!"{selector} is SVG" (← namespaceOf root selector) svgNamespace
  for selector in ["main", "#html", "#input", "#hole-html", "#built-html", "#built-outside"] do
    checkEq s!"{selector} is HTML" (← namespaceOf root selector) htmlNamespace

  let attr (selector name : String) : IO (Option String) := do
    (← findAny root selector).getAttribute name
  checkEq "static attributes keep their case" (← attr "#chart" "viewBox") (some "0 0 10 10")
  checkEq "attribute holes keep their case" (← attr "#chart" "preserveAspectRatio") (some "none")
  checkEq "`class` works, though its property is read-only" (← attr "#chart" "class") (some "a")
  checkEq "attribute holes on a fragment work" (← attr "#fragment" "width") (some "10")
  checkEq "hyphenated attributes work" (← attr "#dot" "stroke-width") (some "1")
  let dot ← findAny root "#dot"
  fire dot "click"
  settle
  check "updates keep the same elements" (JsValue.strictEq (← findAny root "#dot").val dot.val)
  checkEq "attribute holes update" (← attr "#dot" "r") (some "2")
  checkEq "`class` updates" (← attr "#chart" "class") (some "a b")
  checkEq "an absent option removes the attribute" (← attr "#fragment" "width") none
  checkEq "text holes update" (← (← findAny root "#label").textContent) "2"
  checkEq "holes in `title` update" (← (← findAny root "#fragment title").textContent) "2"
  checkEq "live properties in `foreignObject` update"
    (← fromJs (← (← find root "#input").val.get "value") : String) "2"
  fire (← findAny root "#fragment") "click"
  settle
  checkEq "events reach handlers on SVG elements" (← attr "#page" "data-clicks") (some "1")
  checkEq "an event's target tag is in uppercase for SVG too" (← attr "#page" "data-target") (some "RECT")

def main : IO Unit := do
  discard <| EAsync.toBaseIO do
    try
      run
      IO.println "finished"
    catch e =>
      IO.println s!"FAIL threw: {e}"
