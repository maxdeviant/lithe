module

public import Lithe.Core

open Lithe

/-! The state and the page, which the server and the client share, so this can't import `Lithe`. -/

public section

/-- The state of the page, which the server sends to the client. -/
structure Model where
  count : Nat
  /-- A title, which has characters that have to be escaped in HTML and in a `script` element. -/
  title : String
  deriving ToJson

/-- The changes that the page can ask for. -/
inductive Msg where
  | increment
  | decrement

/-- Returns the state after `msg`. -/
def update (msg : Msg) (m : Model) : Model :=
  match msg with
  | .increment => { m with count := m.count + 1 }
  | .decrement => { m with count := m.count - 1 }

/-- Returns the state to start from with the count `count`. -/
def initial (count : Nat := 3) : Model :=
  { count, title := "Count </script> & <more>" }

/-- Returns the page for `m`. -/
def view (m : Model) : Html Msg :=
  <main>
    <h1>{m.title}</h1>
    <button id="decrement" onclick={Msg.decrement}>−</button>
    <output id="count">{m.count}</output>
    <button id="increment" onclick={Msg.increment} use={Action.focus}>+</button>
    <svg viewBox="0 0 10 1" role="img" aria-label="The count, as a bar">
      <rect id="bar" width={m.count} height="1" />
    </svg>
  </main>
