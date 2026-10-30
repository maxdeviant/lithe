import Js
import Lithe.Cmd
import Lithe.Dom
import Lithe.Subscription

/-!
Running an app: the loop that sends messages to `update`, and shows the result of `view`.
-/

open Std.Async

namespace Lithe

/-- An app, which is entirely pure: it describes its state changes, effects, and page as data. -/
structure App (Model Msg : Type) where
  /-- The initial state, and the effects to start with. -/
  init : Model × Cmd Msg
  /-- Returns the state after a message, and the effects to perform. -/
  update : Msg → Model → Model × Cmd Msg
  /-- Returns the page for a state. -/
  view : Model → Html Msg
  /-- Returns the outside events to listen to in a state. -/
  subscriptions : Model → Subscription Msg := fun _ => .none

/-- Returns an app without effects, whose messages are the state changes themselves. -/
def App.simple (init : Model) (view : Model → Html (Model → Model))
    (subscriptions : Model → Subscription (Model → Model) := fun _ => .none) :
    App Model (Model → Model) where
  init := (init, .none)
  update f m := (f m, .none)
  view := view
  subscriptions := subscriptions

/-- A source of outside events that an app has started. -/
structure App.RunningSource (Msg : Type) where
  /-- The latest handler, which the source's events go to. -/
  handler : IO.Ref (Handler Msg)
  /-- Stops the source. -/
  stop : IO Unit

/-- The state of a running app. -/
structure App.Running (Model Msg : Type) where
  app : App Model Msg
  model : IO.Ref Model
  /-- The latest generation of effects under each key. -/
  generations : IO.Ref (Std.HashMap String Nat)
  /-- Whether a render is scheduled. -/
  scheduled : IO.Ref Bool
  /-- The JS function that renders, which is created once. -/
  renderJs : IO.Ref JsValue
  /-- The sources that are running, by ID. -/
  sources : IO.Ref (Std.HashMap String (RunningSource Msg))

@[extern js inline "(queueMicrotask(#1), 0)"]
private opaque queueMicrotask (f : @& JsValue) : BaseIO Unit

namespace App.Running

/-- Schedules a render, so that all of the messages sent in one turn lead to one render. -/
def schedule (r : Running Model Msg) : IO Unit := do
  unless ← r.scheduled.swap true do
    queueMicrotask (← r.renderJs.get)

mutual

/-- Performs `cmd`, sending the message of each of its effects. -/
partial def perform (r : Running Model Msg) (cmd : Cmd Msg) : IO Unit := do
  for effect in cmd.effects do
    let generation? ← effect.key.mapM fun key =>
      r.generations.modifyGet fun gens =>
        let next := gens.getD key 0 + 1
        (next, gens.insert key next)
    discard <| EAsync.toBaseIO do
      let msg ← effect.run
      if let (some key, some generation) := (effect.key, generation?) then
        if (← r.generations.get).getD key 0 != generation then
          return
      try
        dispatch r msg
      catch e =>
        IO.eprintln s!"Lithe: error while handling a message: {e}"

/-- Updates the state for `msg`, and starts its effects. -/
partial def dispatch (r : Running Model Msg) (msg : Msg) : IO Unit := do
  let cmd ← r.model.modifyGet fun model =>
    let (model, cmd) := r.app.update msg model
    (cmd, model)
  perform r cmd
  schedule r

end

/--
Starts `source`. A source that fails to start still counts as running, so that it isn't retried on
every render.
-/
def startSource (r : Running Model Msg) (source : Subscription.Source Msg) :
    IO (RunningSource Msg) := do
  let handler ← IO.mkRef source.handler
  let send (e : Event) : IO Bool := do
    let h ← handler.get
    if let some msg := h.run e then
      dispatch r msg
    return h.preventDefault
  try
    return { handler, stop := ← source.start send }
  catch e =>
    IO.eprintln s!"Lithe: error while starting the subscription {source.key}: {e}"
    return { handler, stop := pure () }

/--
Starts and stops sources to match the current state, and points those that keep running at their
latest handlers. Sources with the same key are told apart by their position among them.
-/
def syncSources (r : Running Model Msg) : IO Unit := do
  let mut counts : Std.HashMap String Nat := {}
  let mut wanted : Array (String × Subscription.Source Msg) := #[]
  for source in (r.app.subscriptions (← r.model.get)).sources do
    let n := counts.getD source.key 0
    counts := counts.insert source.key (n + 1)
    wanted := wanted.push (s!"{source.key}\x00{n}", source)
  for (id, running) in ← r.sources.get do
    unless wanted.any (·.1 == id) do
      r.sources.modify (·.erase id)
      try
        running.stop
      catch e =>
        IO.eprintln s!"Lithe: error while stopping a subscription: {e}"
  for (id, source) in wanted do
    if let some running := (← r.sources.get)[id]? then
      running.handler.set source.handler
    else
      let running ← r.startSource source
      r.sources.modify (·.insert id running)

end App.Running

/-- Starts `app`, which takes over the contents of `root`. -/
def App.mount (app : App Model Msg) (root : Js.Dom.Element) : IO Unit := do
  let (model, cmd) := app.init
  let r : Running Model Msg := {
    app
    model := ← IO.mkRef model
    generations := ← IO.mkRef {}
    scheduled := ← IO.mkRef false
    renderJs := ← IO.mkRef .undefined
    sources := ← IO.mkRef {}
  }
  let rt ← Runtime.new root.val (App.Running.dispatch r)
  let mounted ← IO.mkRef (Mounted.empty : Mounted Msg)
  let render : IO Unit := do
    r.scheduled.set false
    let html := app.view (← r.model.get)
    let old ← mounted.swap .empty
    mounted.set (← rt.patch root.val .null old html)
    rt.runActions
    r.syncSources
  r.renderJs.set (← toJs render)
  Raw.clearChildren root.val
  render
  App.Running.perform r cmd

/-- Starts `app` in the element with the ID `id`, throwing an error if there is none. -/
def App.mountById (app : App Model Msg) (id : String) : IO Unit := do
  let some root ← (← Js.Dom.document).getElementById id
    | throw (.userError s!"no element with ID {id}")
  app.mount root

end Lithe
