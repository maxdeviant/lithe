import LitheTest.Util

open Lithe LitheTest
open Js.Dom
open Std.Async

/-! Checks starting, stopping, and delivering the events of subscriptions. -/

initialize log : IO.Ref (Array String) ← IO.mkRef #[]
initialize sends : IO.Ref (Array (Lithe.Event → IO Bool)) ← IO.mkRef #[]

@[extern js inline "new Promise((resolve) => setTimeout(resolve, Number(#1)))"]
opaque delayPromise (ms : @& Nat) : BaseIO JsValue

def delay (ms : Nat) : Async Unit := do
  discard <| JsValue.await (← delayPromise ms)

inductive Msg where
  | setKeys (keys : Array String)
  | setLabel (label : String)
  | got (s : String)
  | setTimer (on : Bool)
  | setWindow (on : Bool)
  | setFrames (on : Bool)
  | setBroken (on : Bool)
  | tick
  | frame

structure Model where
  keys : Array String := #["a"]
  label : String := "one"
  got : Array String := #[]
  timer : Bool := false
  window : Bool := false
  frames : Bool := false
  broken : Bool := false
  ticks : Nat := 0
  frameCount : Nat := 0

def update : Msg → Model → Model × Cmd Msg
  | .setKeys keys, m => ({ m with keys }, .none)
  | .setLabel label, m => ({ m with label }, .none)
  | .got s, m => ({ m with got := m.got.push s }, .none)
  | .setTimer timer, m => ({ m with timer }, .none)
  | .setWindow window, m => ({ m with window }, .none)
  | .setFrames frames, m => ({ m with frames }, .none)
  | .setBroken broken, m => ({ m with broken }, .none)
  | .tick, m => ({ m with ticks := m.ticks + 1 }, .none)
  | .frame, m => ({ m with frameCount := m.frameCount + 1 }, .none)

/-- A source that records when it starts and stops, and that the test sends events to directly. -/
def recorded (key label : String) : Subscription Msg :=
  .source key (fun (e : Lithe.Event) => Msg.got s!"{label}:{e.value}") fun send => do
    log.modify (·.push s!"start {key}")
    sends.modify (·.push send)
    return log.modify (·.push s!"stop {key}")

def onKey (e : Lithe.Event) : Msg :=
  .got s!"key:{e.key}"

def subscriptions (m : Model) : Subscription Msg :=
  .batch #[
    .batch (m.keys.map (recorded · m.label)),
    if m.timer then .every 2 Msg.tick else .none,
    if m.window then .onWindow "keydown" (preventDefault onKey : Handler Msg) else .none,
    if m.frames then .animationFrame Msg.frame else .none,
    if m.broken then
      .source "broken" Msg.tick fun _ => throw (.userError "boom")
    else
      .none,
    (.onDocument "custom" "mapped" : Subscription String).map Msg.got]

def view (m : Model) : Html Msg :=
  <div>
    <button id="ab" onclick={Msg.setKeys #["a", "b"]}>k</button>
    <button id="b" onclick={Msg.setKeys #["b"]}>k</button>
    <button id="bb" onclick={Msg.setKeys #["b", "b"]}>k</button>
    <button id="none" onclick={Msg.setKeys #[]}>k</button>
    <button id="label" onclick={Msg.setLabel "two"}>l</button>
    <button id="timer-on" onclick={Msg.setTimer true}>t</button>
    <button id="timer-off" onclick={Msg.setTimer false}>t</button>
    <button id="window-on" onclick={Msg.setWindow true}>w</button>
    <button id="window-off" onclick={Msg.setWindow false}>w</button>
    <button id="frames-on" onclick={Msg.setFrames true}>f</button>
    <button id="frames-off" onclick={Msg.setFrames false}>f</button>
    <button id="broken-on" onclick={Msg.setBroken true}>b</button>
    <p id="got">{" ".intercalate m.got.toList}</p>
    <p id="ticks">{m.ticks}</p>
    <p id="frames">{m.frameCount}</p>
  </div>

def text (root : Element) (selector : String) : IO String := do
  (← find root selector).textContent

def number (root : Element) (selector : String) : IO Nat := do
  return (← text root selector).toNat!

def click (root : Element) (selector : String) : Async Unit := do
  clickOn root selector
  settle

/-- Sends an event with the value `value` through the most recently started source. -/
def sendLatest (value : String) : Async Unit := do
  let some send := (← sends.get).back? | throw (.userError "no sources")
  discard <| send { value }
  settle

def checkSources (root : Element) : Async Unit := do
  checkEq "starting the app starts its sources" (← log.get) #["start a"]
  click root "#label"
  checkEq "a rerender keeps a source running" (← log.get) #["start a"]
  sendLatest "x"
  checkEq "events go to the latest handler" (← text root "#got") "two:x"
  click root "#ab"
  checkEq "a new key starts a source" (← log.get) #["start a", "start b"]
  click root "#b"
  checkEq "a key that goes away stops its source" (← log.get)
    #["start a", "start b", "stop a"]
  click root "#bb"
  checkEq "another source with the same key starts separately" (← log.get)
    #["start a", "start b", "stop a", "start b"]
  click root "#b"
  checkEq "sources with the same key stop separately" (← log.get)
    #["start a", "start b", "stop a", "start b", "stop b"]
  click root "#none"
  checkEq "the last source stops" (← log.get)
    #["start a", "start b", "stop a", "start b", "stop b", "stop b"]

def checkTimer (root : Element) : Async Unit := do
  click root "#timer-on"
  delay 30
  settle
  let ticks ← number root "#ticks"
  check "`every` sends messages repeatedly" (ticks >= 2)
  click root "#timer-off"
  let stopped ← number root "#ticks"
  delay 30
  settle
  checkEq "`every` stops" (← number root "#ticks") stopped

def checkWindow (root : Element) : Async Unit := do
  let win ← Raw.window
  let event ← JsValue.new (← JsValue.getGlobal "KeyboardEvent")
    #[.ofString "keydown", ← JsValue.ofEntries #[
      ("key", .ofString "k"), ("cancelable", .ofBool true)]]
  click root "#window-on"
  discard <| win.callMethod "dispatchEvent" #[event]
  settle
  check "`onWindow` sends messages" ((← text root "#got").endsWith "key:k")
  checkEq "`onWindow` follows `preventDefault`"
    (← (fromJs (← event.get "defaultPrevented") : IO Bool)) true
  click root "#window-off"
  let before ← text root "#got"
  discard <| win.callMethod "dispatchEvent" #[event]
  settle
  checkEq "`onWindow` stops" (← text root "#got") before

def checkMapped (root : Element) : Async Unit := do
  fire (← document).toEventTarget "custom"
  settle
  check "`map` and `onDocument` deliver messages" ((← text root "#got").endsWith "mapped")

def checkFrames (root : Element) : Async Unit := do
  click root "#frames-on"
  delay 100
  settle
  check "`animationFrame` sends messages repeatedly" ((← number root "#frames") >= 2)
  click root "#frames-off"
  let stopped ← number root "#frames"
  delay 60
  settle
  checkEq "`animationFrame` stops" (← number root "#frames") stopped

def checkBroken (root : Element) : Async Unit := do
  click root "#broken-on"
  click root "#ab"
  check "a source that fails to start doesn't stop the others"
    ((← log.get).back? == some "start b")

def run : Async Unit := do
  let root ← newRoot
  let app : App Model Msg := { init := ({}, .none), update, view, subscriptions }
  app.mount root
  checkSources root
  checkTimer root
  checkWindow root
  checkMapped root
  checkFrames root
  checkBroken root

def main : IO Unit := do
  discard <| EAsync.toBaseIO do
    try
      run
      IO.println "finished"
    catch e =>
      IO.println s!"FAIL threw: {e}"
