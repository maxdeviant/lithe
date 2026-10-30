import Js
import Lithe

open Std.Async
open Js.Dom

namespace LitheTest

/-- Prints whether `ok` holds, which the test runner looks for. -/
def check (name : String) (ok : Bool) : IO Unit :=
  IO.println s!"{if ok then "ok  " else "FAIL"} {name}"

/-- Prints whether `actual` is `expected`, showing both if not. -/
def checkEq [BEq α] [ToString α] (name : String) (actual expected : α) : IO Unit :=
  if actual == expected then
    IO.println s!"ok   {name}"
  else
    IO.println s!"FAIL {name}\n  expected: {expected}\n  actual:   {actual}"

/-- Lets pending microtasks run, including any scheduled render. -/
def settle : Async Unit := do
  for _ in [0:5] do
    discard <| JsValue.await (.ofNat 0)

/-- Creates a new element in the page to render into. -/
def newRoot : IO Element := do
  let doc ← document
  let root ← doc.createElement "div"
  let some body ← doc.body | throw (.userError "no body")
  body.appendChild root
  return root

/-- Returns the markup inside of `e`. -/
def innerHtml (e : Element) : IO String := do
  fromJs (← e.val.get "innerHTML")

/-- Returns the first element in `root` that matches `selector`. -/
def find (root : Element) (selector : String) : IO HtmlElement := do
  let some e ← root.querySelector selector | throw (.userError s!"no match for {selector}")
  e.cast HtmlElement

/-- Dispatches a bubbling event of the type `type` to `t`. -/
def fire (t : EventTarget) (type : String) (bubbles := true) : IO Unit := do
  discard <| t.dispatchEvent (← Event.new type { bubbles, cancelable := true })

/-- Clicks `root`'s first match for `selector`. -/
def clickOn (root : Element) (selector : String) : IO Unit := do
  fire (← find root selector) "click"

end LitheTest
