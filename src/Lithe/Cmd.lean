import Std.Async.Basic

/-!
Effects, which an app's `update` describes as data, and the app's runtime performs.
-/

open Std.Async

namespace Lithe

/-- An effect that eventually produces a message. -/
structure Cmd.Effect (Msg : Type) where
  /-- Performs the effect. -/
  run : Async Msg
  /-- If set, a later effect with the same key makes the message of this one be dropped. -/
  key : Option String := none

/-- Effects to perform, which run concurrently and each send their message when they finish. -/
structure Cmd (Msg : Type) where
  /-- The effects. -/
  effects : Array (Cmd.Effect Msg) := #[]

namespace Cmd

/-- No effects. -/
def none : Cmd Msg := {}

/-- Sends `msg` without doing anything else. -/
def ofMsg (msg : Msg) : Cmd Msg :=
  { effects := #[{ run := pure msg }] }

/--
Performs `action`, and sends the message for its outcome. An error is part of the message, so it
can't go unnoticed.
-/
def attempt (action : Async α) (f : Except IO.Error α → Msg) : Cmd Msg :=
  { effects := #[{
      run := do
        try
          return f (.ok (← action))
        catch e =>
          return f (.error e) }] }

/-- Performs all of `cmds`. -/
def batch (cmds : Array (Cmd Msg)) : Cmd Msg :=
  { effects := cmds.flatMap (·.effects) }

/--
Returns `cmd` with its effects superseding any that started earlier under `key`, whose messages are
then dropped. The earlier effects still run to completion, as tasks can't be canceled.
-/
def latest (key : String) (cmd : Cmd Msg) : Cmd Msg :=
  { effects := cmd.effects.map ({ · with key := some key }) }

/-- Returns `cmd` with the transformation `f` applied to its messages. -/
def map (f : α → β) (cmd : Cmd α) : Cmd β :=
  { effects := cmd.effects.map fun e => { run := f <$> e.run, key := e.key } }

end Cmd

end Lithe
