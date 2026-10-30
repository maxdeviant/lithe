/-- An item on the list. -/
structure Todo where
  id : Nat
  text : String
  done : Bool := false

/-- The state of the app. -/
structure Model where
  todos : Array Todo := #[]
  nextId : Nat := 0
  /-- The text of the item being written. -/
  draft : String := ""

/-- The changes that the page can ask for. -/
inductive Msg where
  | setDraft (text : String)
  | add
  | toggle (id : Nat)
  | remove (id : Nat)
  | clearCompleted

/-- Returns the state after `msg`. -/
def Model.update (m : Model) : Msg → Model
  | .setDraft text => { m with draft := text }
  | .add =>
    let text := m.draft.trimAscii.copy
    if text.isEmpty then
      m
    else
      { todos := m.todos.push { id := m.nextId, text }, nextId := m.nextId + 1, draft := "" }
  | .toggle id =>
    { m with todos := m.todos.map fun t => if t.id == id then { t with done := !t.done } else t }
  | .remove id => { m with todos := m.todos.filter (·.id != id) }
  | .clearCompleted => { m with todos := m.todos.filter (!·.done) }

/-- Returns the number of items that are not checked off. -/
def Model.itemsLeft (m : Model) : Nat :=
  (m.todos.filter (!·.done)).size

/-- Toggling an item never adds or removes any. -/
theorem Model.update_toggle_size (m : Model) (id : Nat) :
    (m.update (.toggle id)).todos.size = m.todos.size := by
  simp [Model.update]

/-- Clearing the completed items keeps every item that is left to do. -/
theorem Model.itemsLeft_clearCompleted (m : Model) :
    (m.update .clearCompleted).itemsLeft = m.itemsLeft := by
  simp [Model.update, Model.itemsLeft]
