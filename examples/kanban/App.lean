import Lithe
import Kanban.Model
import Kanban.View

open Lithe

/-- Returns the message for a keyboard shortcut, if `e` is one. Text fields have their own undo. -/
def shortcut (e : Lithe.Event) : Option Msg :=
  if ["INPUT", "TEXTAREA", "SELECT"].contains e.targetTag || !(e.ctrlKey || e.metaKey) then
    none
  else if e.key.toLower == "z" then
    some (if e.shiftKey then .redo else .undo)
  else
    none

/-- Returns the message for the URL in `e.value` changing. -/
def routeChangedTo (e : Lithe.Event) : Msg :=
  .routeChanged (Route.parse e.value)

/-- Listens for changes to the URL, sending events whose `value` is the new hash. -/
def onHashChange : Subscription Msg :=
  .source "hashchange" routeChangedTo fun send => do
    let onChange : JsValue → IO Unit := fun _ => do
      discard <| send { type := "hashchange", value := ← currentHash }
    let window ← Raw.window
    let listener ← toJs onChange
    Raw.addEventListener window "hashchange" listener false
    return Raw.removeEventListener window "hashchange" listener

/-- The shortcuts aren't for the page behind an open dialog. -/
def subscriptions (m : Model) : Subscription Msg :=
  .batch #[onHashChange, if m.editor.isNone then .onWindow "keydown" shortcut else .none]

/-- Returns the app, starting from the board and the problem with loading it, if any. -/
def app (board : Board) (problem : Option String) (route : Route) : App Model Msg where
  init := Model.goTo { board, problem } route
  update msg m := m.update msg
  view := view
  subscriptions := subscriptions

def main : IO Unit := do
  let (board, problem) ←
    try
      pure ((← loadBoard).getD .sample, none)
    catch e =>
      pure (.sample, some s!"Couldn't read the saved board, so this is a new one: {e}")
  (app board problem (Route.parse (← currentHash))).mountById "app"
