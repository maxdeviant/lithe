import LitheTest.Util

open Lithe LitheTest
open Js.Dom
open Std.Async

/-! Checks actions and commands. -/

initialize actionLog : IO.Ref (Array String) ← IO.mkRef #[]

def logAction (name : String) : Action := fun h => do
  let connected ← (fromJs (← h.toElement.val.get "isConnected") : IO Bool)
  actionLog.modify (·.push s!"{name} connected={connected}")
  return actionLog.modify (·.push s!"{name} cleaned up")

inductive Msg where
  | setVisible (on : Bool)
  | got (s : String)
  | run (which : Nat)

structure Model where
  visible : Bool := true
  got : Array String := #[]

def after (rounds : Nat) (s : String) : Async String := do
  for _ in [0:rounds] do
    settle
  return s

def describe : Except IO.Error String → Msg
  | .ok s => .got s
  | .error e => .got s!"error: {e}"

/-- The commands that each button starts. -/
def plain : Cmd Msg := .batch #[.ofMsg (.got "a"), .attempt (after 1 "b") describe]

def failing : Cmd Msg := .attempt (throw (.userError "boom") : Async String) describe

def superseded : Cmd Msg := .batch #[
  .latest "search" (.attempt (after 3 "old") describe),
  .latest "search" (.attempt (after 1 "new") describe)]

def update : Msg → Model → Model × Cmd Msg
  | .setVisible on, m => ({ m with visible := on }, .none)
  | .got s, m => ({ m with got := m.got.push s }, .none)
  | .run 0, m => (m, plain)
  | .run 1, m => (m, failing)
  | .run _, m => (m, superseded)

def view (m : Model) : Html Msg :=
  <div>
    {if m.visible then <input id="a" use={logAction "a"} use={Action.focus} /> else Html.empty}
    <button id="hide" onclick={Msg.setVisible false}>h</button>
    <button id="show" onclick={Msg.setVisible true}>s</button>
    <button id="plain" onclick={Msg.run 0}>p</button>
    <button id="failing" onclick={Msg.run 1}>f</button>
    <button id="superseded" onclick={Msg.run 2}>s</button>
    {(<button id="mapped" onclick={"mapped"}>m</button> : Html String).map Msg.got}
    <p id="got">{" ".intercalate m.got.toList}</p>
  </div>

def checkMapped (root : Element) : Async Unit := do
  clickOn root "#mapped"
  settle
  checkEq "`Html.map` transforms messages" (← (← find root "#got").textContent)
    "init a b error: boom new mapped"

def run : Async Unit := do
  let root ← newRoot
  let app : App Model Msg := { init := ({}, .ofMsg (.got "init")), update, view }
  app.mount root
  checkEq "actions run after mounting, once in the page" (← actionLog.get) #["a connected=true"]
  let active ← (← document).val.get "activeElement"
  check "`Action.focus` focuses the element" (JsValue.strictEq active (← find root "#a").val)
  settle
  checkEq "initial commands send messages" (← (← find root "#got").textContent) "init"

  clickOn root "#hide"
  settle
  checkEq "removal runs the cleanup" (← actionLog.get) #["a connected=true", "a cleaned up"]
  clickOn root "#show"
  settle
  checkEq "remounting runs the action again" (← actionLog.get)
    #["a connected=true", "a cleaned up", "a connected=true"]

  clickOn root "#plain"
  settle
  settle
  checkEq "effects send their messages" (← (← find root "#got").textContent) "init a b"
  checkEq "rerendering doesn't rerun actions" (← actionLog.get)
    #["a connected=true", "a cleaned up", "a connected=true"]

  clickOn root "#failing"
  settle
  checkEq "errors become messages" (← (← find root "#got").textContent) "init a b error: boom"

  clickOn root "#superseded"
  settle
  settle
  settle
  settle
  checkEq "`latest` drops superseded results" (← (← find root "#got").textContent)
    "init a b error: boom new"
  checkMapped root

def main : IO Unit := do
  discard <| EAsync.toBaseIO do
    try
      run
      IO.println "finished"
    catch e =>
      IO.println s!"FAIL threw: {e}"
