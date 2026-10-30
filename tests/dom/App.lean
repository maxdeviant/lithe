import LitheTest.Util

open Lithe LitheTest
open Js.Dom
open Std.Async

/-! Checks rendering, updates, and events through a running app. -/

structure Model where
  count : Nat := 0
  draft : String := ""
  on : Bool := false
  log : Array String := #[]
  deriving Inhabited

abbrev Up := Model → Model

def logged (s : String) : Up := fun m => { m with log := m.log.push s }

def setDraft (s : String) : Up := fun m => { m with draft := s }

def setOn (b : Bool) : Up := fun m => { m with on := b }

def view (m : Model) : Html Up :=
  <div id="app" class={#["app", cls "on" m.on]} data-count={m.count} title={if m.on then some "t" else none}>
    <p id="commented">a{/- note -/}b<i>{/- note -/}c</i>{/- note -/}{m.count}</p>
    <button id="inc" onclick={(fun (m : Model) => { m with count := m.count + 1 })}>{m.count}</button>
    <input id="text" value={m.draft} oninput={setDraft} />
    <input id="box" type="checkbox" checked={m.on} onchange={setOn} />
    <button id="toggle" disabled={m.on} onclick={(fun (m : Model) => { m with on := !m.on })}>toggle</button>
    <section onclick={logged "section"}>
      <button id="bubble" onclick={logged "inner"}>a</button>
      <button id="stop" onclick={stopPropagation (logged "stopped")}>b</button>
    </section>
    <form id="form" onsubmit={preventDefault (logged "submit")}></form>
    <input id="focus" onfocus={logged "focus"} onkeydown={fun (e : Lithe.Event) => if e.key == "Enter" then some (logged "enter") else none} />
    <p id="draft">{m.draft}</p>
    <p id="log">{" ".intercalate m.log.toList}</p>
  </div>

def run : Async Unit := do
  let root ← newRoot
  (App.simple ({} : Model) view).mount root

  let inc ← find root "#inc"
  checkEq "the first render is synchronous" (← inc.textContent) "0"
  clickOn root "#inc"
  clickOn root "#inc"
  checkEq "messages render in a batch, later" (← inc.textContent) "0"
  settle
  checkEq "text holes update" (← inc.textContent) "2"
  checkEq "holes after comments update" (← (← find root "#commented").textContent) "abc2"
  checkEq "attribute holes update" (← (← find root "#app").getAttribute "data-count") (some "2")
  check "updates keep the same elements" (JsValue.strictEq (← find root "#inc").val inc.val)

  let text ← (← find root "#text").cast HtmlInputElement
  text.setValue "hello"
  fire text "input"
  settle
  checkEq "input handlers get the value" (← (← find root "#draft").textContent) "hello"

  let box ← (← find root "#box").cast HtmlInputElement
  check "the class list starts without `on`" !(← (← find root "#app").classList.contains "on")
  checkEq "an absent option has no attribute" (← (← find root "#app").getAttribute "title") none
  box.setChecked true
  fire box "change"
  settle
  check "change handlers get the checked state" (← (← find root "#app").classList.contains "on")
  checkEq "an option with a value sets the attribute" (← (← find root "#app").getAttribute "title") (some "t")
  check "`true` adds a boolean attribute" (← (← find root "#toggle").hasAttribute "disabled")
  clickOn root "#toggle"
  settle
  check "`false` removes a boolean attribute" !(← (← find root "#toggle").hasAttribute "disabled")
  check "`checked` follows the model" !(← box.checked)
  box.setChecked true
  (← find root "#inc").click
  settle
  check "a live property is restored even if its hole didn't change" !(← box.checked)

  clickOn root "#bubble"
  settle
  checkEq "events bubble through handlers" (← (← find root "#log").textContent) "inner section"
  clickOn root "#stop"
  settle
  checkEq "`stopPropagation` stops the walk" (← (← find root "#log").textContent) "inner section stopped"

  let submit ← Event.new "submit" { bubbles := true, cancelable := true }
  let notPrevented ← (← find root "#form").dispatchEvent submit
  check "`preventDefault` cancels the event" !notPrevented

  fire (← find root "#focus") "focus" (bubbles := false)
  settle
  check "events that don't bubble reach their target"
    (((← (← find root "#log").textContent).splitOn " ").contains "focus")
  let press (key : String) : IO Unit := do
    discard <| (← find root "#focus").dispatchEvent
      (← KeyboardEvent.new "keydown" { bubbles := true, key })
  press "a"
  settle
  check "a handler can choose not to send a message"
    !(((← (← find root "#log").textContent).splitOn " ").contains "enter")
  press "Enter"
  settle
  check "keyboard handlers get the key"
    (((← (← find root "#log").textContent).splitOn " ").contains "enter")

def main : IO Unit := do
  discard <| EAsync.toBaseIO do
    try
      run
      IO.println "finished"
    catch e =>
      IO.println s!"FAIL threw: {e}"
