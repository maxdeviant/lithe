import Lithe
import Stopwatch.Model
import Stopwatch.View

open Lithe

/-- Returns the message for a keyboard shortcut, if `e` is one. -/
def shortcut (e : Lithe.Event) : Option Msg :=
  match e.key with
  | "s" => some (.toggle e.timeStamp)
  | "l" => some .lap
  | "r" => some .reset
  | _ => none

/-- Returns the message for a tick of the timer. -/
def tickAt (e : Lithe.Event) : Msg :=
  .tick e.timeStamp

/-- The timer only runs while the stopwatch does. -/
def subscriptions (m : Model) : Subscription Msg :=
  .batch #[
    .onWindow "keydown" shortcut,
    if m.running then .every 100 tickAt else .none]

def app : App Model Msg where
  init := ({}, .none)
  update msg m := (m.update msg, .none)
  view := view
  subscriptions := subscriptions

def main : IO Unit :=
  app.mountById "app"
