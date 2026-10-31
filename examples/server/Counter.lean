import Lithe.Core

open Lithe

/-! The state and the page, which the server and the client share, so this can't import `Lithe`. -/

/-- The changes that the page can ask for. -/
inductive Msg where
  | increment
  | decrement

/-- Returns the state after `msg`. -/
def update : Msg → Nat → Nat
  | .increment, n => n + 1
  | .decrement, n => n - 1

/-- The state that the page starts in, on both sides. -/
def initial : Nat := 3

/-- Returns the page for `count`. -/
def view (count : Nat) : Html Msg :=
  <main>
    <button id="decrement" onclick={Msg.decrement}>−</button>
    <output id="count">{count}</output>
    <button id="increment" onclick={Msg.increment} use={Action.focus}>+</button>
    <svg viewBox="0 0 10 1" role="img" aria-label="The count, as a bar">
      <rect id="bar" width={count} height="1" />
    </svg>
  </main>
