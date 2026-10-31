module

public import Lithe.Html

/-!
Subscriptions, which describe the outside events that an app listens to in a given state.
-/

@[expose] public section

namespace Lithe

/-- A source of outside events. -/
structure Subscription.Source (Msg : Type) where
  /-- Identifies the source, which keeps running for as long as its key stays subscribed. -/
  key : String
  /--
  Starts the source, and returns what stops it. The function it receives delivers an event, and
  returns whether the event's default action should be canceled.
  -/
  start : (Event → IO Bool) → IO (IO Unit)
  /-- How to respond to the source's events. Stopping propagation has no effect. -/
  handler : Handler Msg

/-- The outside events to listen to. -/
structure Subscription (Msg : Type) where
  /-- The sources of the events. -/
  sources : Array (Subscription.Source Msg) := #[]

namespace Subscription

/-- No events. -/
def none : Subscription Msg := {}

/-- Listens to all of `subs`. -/
def batch (subs : Array (Subscription Msg)) : Subscription Msg :=
  { sources := subs.flatMap (·.sources) }

/--
Listens to the source that `start` starts. The source isn't restarted while `key` stays subscribed,
so the key must include anything that `start` depends on. The handler is always the latest one.
-/
def source [ToHandler α Msg] (key : String) (a : α) (start : (Event → IO Bool) → IO (IO Unit)) :
    Subscription Msg :=
  { sources := #[{ key, start, handler := ToHandler.toHandler a }] }

/-- Returns `sub` with the transformation `f` applied to its messages. -/
def map (f : α → β) (sub : Subscription α) : Subscription β :=
  { sources := sub.sources.map fun s => { s with handler := s.handler.map f } }

end Subscription

end Lithe
