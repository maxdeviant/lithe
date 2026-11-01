module

import Lithe.Core
import LitheTest.JsonCases

open Lithe

/-! A native program using everything in `Lithe.Core`. It fails to link if any of it needs JS. -/

inductive Msg where
  | increment
  | set (s : String)

/-- A view with the kinds of things that views that are shared with a client have in them. -/
def view (count : Nat) : Html Msg :=
  <main class={#["a", cls "b" (count == 3)]}>
    <button onclick={Msg.increment} use={Action.focus}>+</button>
    <input value={toString count} oninput={Msg.set} />
    <svg viewBox="0 0 1 1"><rect width={count} /></svg>
    <select value={"b"} onchange={preventDefault Msg.set}>
      <option value="a">A</option>
      <option value="b">B</option>
    </select>
    {Html.forEach #["x"] id fun s => <span>é{s}</span>}
  </main>

/-- A page with the kinds of things that a static site has, around a part that a client takes over. -/
def page (name : String) : Document Unit :=
  <html lang="en">
    <head>
      <meta property="og:title" content={name} />
      <title>{name} · {(1 : Nat)}</title>
      {Html.inlineScript "a = '</b>'"}
    </head>
    <body>
      <div id="app">{Html.static (view 3)}</div>
      {Html.jsonScript "data" "</script>"}
    </body>
  </html>

/-- Returns whether `actual` is `expected`, printing both if not. -/
def check (name actual expected : String) : IO Bool := do
  if actual == expected then
    return true
  IO.eprintln s!"FAIL {name}\n  expected: {expected}\n  actual:   {actual}"
  return false

/-- Effects and subscriptions have to work as data, as `update` and `subscriptions` may be shared. -/
def describe : String :=
  let cmd : Cmd Nat := .batch #[.ofMsg 1, .latest "k" (.ofMsg 2)]
  let sub : Subscription Nat :=
    .batch #[.none, .source "s" (2 : Nat) fun _ => pure (pure ())]
  s!"{cmd.effects.size} {(sub.map (· + 1)).sources.map (·.key)}"

/-- A value of the type that native programs never have a real one of. -/
unsafe def fakeHandleImpl : ElementHandle := unsafeCast ()

@[implemented_by fakeHandleImpl] opaque fakeHandle : ElementHandle

public def main : IO UInt32 := do
  let rendered ← check "rendering" (view 3).render
    ("<main class=\"a b\"><button>+</button><input value=\"3\">" ++
      "<svg viewBox=\"0 0 1 1\"><rect width=\"3\"></rect></svg>" ++
      "<select><option value=\"a\">A</option><option value=\"b\" selected>B</option></select>" ++
      "<span>éx</span></main>")
  let document ← check "a document" (page "<x>").render
    ("<!doctype html><html lang=\"en\"><head><meta property=\"og:title\" content=\"&lt;x&gt;\">" ++
      "<title>&lt;x&gt; · 1</title><script>a = '<\\/b>'</script></head><body><div id=\"app\">" ++
      (view 3).render ++ "</div><script id=\"data\" type=\"application/json\">\"\\u003c/script>\"</script>" ++
      "</body></html>")
  let described ← check "effects and subscriptions" describe "2 #[s]"
  -- The native side of this extern is otherwise never run.
  let cleanup ← Action.focus fakeHandle
  cleanup
  for failure in LitheTest.JsonCases.failures do
    IO.eprintln s!"FAIL JSON: {failure}"
  for line in LitheTest.JsonCases.transcript do
    IO.println s!"json {line}"
  return if rendered && document && described && LitheTest.JsonCases.failures.isEmpty then 0 else 1
