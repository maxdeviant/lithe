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

/--
Returns a description of what's in `node`, in which adjacent text is joined, and comments are left
out. It covers live properties rather than the attributes that set their initial state.
-/
@[extern js inline
  "$rt.mkString(((root) => { const live = ['value', 'checked', 'selected', 'muted']; const children = (n) => { let out = ''; let text = ''; const flush = () => { if (text) { out += '[' + text + ']'; text = ''; } }; for (const c of n.childNodes) { if (c.nodeType === 3) { text += c.data; } else if (c.nodeType === 1) { flush(); out += element(c); } } flush(); return out; }; const element = (e) => { const attrs = [...e.attributes].filter((a) => !live.includes(a.name)).map((a) => a.name + '=' + a.value).sort(); const props = live.filter((p) => p in e).map((p) => p + ':' + String(e[p])); const inner = e.localName === 'textarea' ? '' : children(e); return '<' + e.namespaceURI + ' ' + e.localName + ' ' + attrs.concat(props).join(' ') + '>' + inner + '</>'; }; return children(root); })(#1))"]
opaque describeDom (node : @& JsValue) : BaseIO String

/-- Returns a description of the DOM that the HTML parser builds from `html`. -/
def describeParsed (html : String) : IO String := do
  let root ← newRoot
  root.val.set "innerHTML" (.ofString html)
  let description ← describeDom root.val
  root.remove
  return description

/-- Dispatches a bubbling event of the type `type` to `t`. -/
def fire (t : EventTarget) (type : String) (bubbles := true) : IO Unit := do
  discard <| t.dispatchEvent (← Event.new type { bubbles, cancelable := true })

/-- Clicks `root`'s first match for `selector`. -/
def clickOn (root : Element) (selector : String) : IO Unit := do
  fire (← find root selector) "click"

end LitheTest
