import Js
import Lithe.Cmd
import Lithe.Dom

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

/-- Returns an app without effects, whose messages are the state changes themselves. -/
def App.simple (init : Model) (view : Model → Html (Model → Model)) : App Model (Model → Model) where
  init := (init, .none)
  update f m := (f m, .none)
  view := view

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
  }
  let rt ← Runtime.new root.val (App.Running.dispatch r)
  let mounted ← IO.mkRef (Mounted.empty : Mounted Msg)
  let render : IO Unit := do
    r.scheduled.set false
    let html := app.view (← r.model.get)
    let old ← mounted.swap .empty
    mounted.set (← rt.patch root.val .null old html)
    rt.runActions
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
