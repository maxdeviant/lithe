import Lithe

open Lithe

/-! The operations of js-framework-benchmark, which `run.js` drives through the buttons. -/

structure Row where
  id : Nat
  label : String
  deriving Inhabited

structure Model where
  rows : Array Row := #[]
  nextId : Nat := 1
  selected : Option Nat := none
  /-- The state of the random number generator, which keeps labels reproducible. -/
  seed : Nat := 42

inductive Msg where
  | create (count : Nat)
  | append (count : Nat)
  | updateEveryTenth
  | clear
  | swap
  | select (id : Nat)
  | remove (id : Nat)

def adjectives : Array String :=
  #["pretty", "large", "big", "small", "tall", "short", "long", "handsome", "plain", "quaint",
    "clean", "elegant", "easy", "angry", "crazy", "helpful", "mushy", "odd", "unsightly", "cheap"]

def colors : Array String :=
  #["red", "yellow", "blue", "green", "pink", "brown", "purple", "white", "black", "orange"]

def nouns : Array String :=
  #["table", "chair", "house", "bbq", "desk", "car", "pony", "cookie", "sandwich", "burger"]

/-- Returns `count` new rows, and the model with their IDs and random numbers used up. -/
def Model.newRows (m : Model) (count : Nat) : Array Row × Model := Id.run do
  let mut seed := m.seed
  let mut rows := Array.emptyWithCapacity count
  for i in [0:count] do
    seed := (seed * 1103515245 + 12345) % 2147483648
    let a := adjectives[seed % adjectives.size]!
    let c := colors[(seed / 32) % colors.size]!
    let n := nouns[(seed / 1024) % nouns.size]!
    rows := rows.push { id := m.nextId + i, label := s!"{a} {c} {n}" }
  return (rows, { m with nextId := m.nextId + count, seed })

def update : Msg → Model → Model × Cmd Msg
  | .create count, m =>
    let (rows, m) := m.newRows count
    ({ m with rows, selected := none }, .none)
  | .append count, m =>
    let (rows, m) := m.newRows count
    ({ m with rows := m.rows ++ rows }, .none)
  | .updateEveryTenth, m =>
    let rows := m.rows.mapIdx fun i r =>
      if i % 10 == 0 then { r with label := r.label ++ " !!!" } else r
    ({ m with rows }, .none)
  | .clear, m => ({ m with rows := #[], selected := none }, .none)
  | .swap, m =>
    if m.rows.size > 998 then
      let a := m.rows[1]!
      let b := m.rows[998]!
      ({ m with rows := (m.rows.set! 1 b).set! 998 a }, .none)
    else
      (m, .none)
  | .select id, m => ({ m with selected := some id }, .none)
  | .remove id, m => ({ m with rows := m.rows.filter (·.id != id) }, .none)

def viewRow (selected : Option Nat) (r : Row) : Html Msg :=
  <tr class={if selected == some r.id then "danger" else ""}>
    <td class="col-md-1">{r.id}</td>
    <td class="col-md-4"><a class="lbl" onclick={Msg.select r.id}>{r.label}</a></td>
    <td class="col-md-1"><a class="remove" onclick={Msg.remove r.id}><span class="icon" aria-hidden="true"></span></a></td>
    <td class="col-md-6"></td>
  </tr>

def view (m : Model) : Html Msg :=
  <div class="container">
    <button id="create" onclick={Msg.create 1000}>Create 1,000 rows</button>
    <button id="createLots" onclick={Msg.create 10000}>Create 10,000 rows</button>
    <button id="append" onclick={Msg.append 1000}>Append 1,000 rows</button>
    <button id="update" onclick={Msg.updateEveryTenth}>Update every 10th row</button>
    <button id="clear" onclick={Msg.clear}>Clear</button>
    <button id="swap" onclick={Msg.swap}>Swap rows</button>
    <table class="table">
      <tbody>{Html.forEach m.rows (·.id) (viewRow m.selected)}</tbody>
    </table>
  </div>

def main : IO Unit :=
  ({ init := ({}, .none), update, view } : App Model Msg).mountById "app"
