import Js

/-! The data on the board, and the operations on it, which know nothing about the page. -/

/-- A way to categorize a card. -/
inductive Label where
  | bug
  | feature
  | chore
  deriving BEq, ToJs, FromJs

/-- Every label, in the order they're shown. -/
def Label.all : Array Label := #[.bug, .feature, .chore]

/-- Returns the name of `l`. -/
def Label.name : Label → String
  | .bug => "bug"
  | .feature => "feature"
  | .chore => "chore"

/-- A vertical list on the board. -/
structure Column where
  id : Nat
  name : String
  deriving BEq, ToJs, FromJs

/-- A piece of work. -/
structure Card where
  id : Nat
  /-- The ID of the column that the card is in. -/
  column : Nat
  title : String
  description : String := ""
  labels : Array Label := #[]
  deriving BEq, ToJs, FromJs

/-- The whole board. -/
structure Board where
  columns : Array Column
  /-- The cards of all columns. Those in the same column are in the order they're shown. -/
  cards : Array Card
  /-- The next ID to give to a column or a card. -/
  nextId : Nat
  deriving BEq, ToJs, FromJs

namespace Board

/-- The board that a new user starts with. -/
def sample : Board where
  columns := #[{ id := 0, name := "To do" }, { id := 1, name := "Doing" }, { id := 2, name := "Done" }]
  cards := #[
    { id := 3, column := 0, title := "Write the release notes", labels := #[.chore] },
    { id := 4, column := 0, title := "Fix the flaky upload test", labels := #[.bug] },
    { id := 5, column := 1, title := "Add dark mode", description := "Follow the system setting.",
      labels := #[.feature] },
    { id := 6, column := 2, title := "Set up CI", labels := #[.chore] }]
  nextId := 7

/-- Returns whether every card is in a column that exists, and all IDs are unique and in use. -/
def isValid (b : Board) : Bool :=
  let ids := b.columns.map (·.id) ++ b.cards.map (·.id)
  b.cards.all (fun c => b.columns.any (·.id == c.column))
    && ids.all (· < b.nextId)
    && ids.toList.Nodup

/-- Returns the card with the ID `id`, if there is one. -/
def card? (b : Board) (id : Nat) : Option Card :=
  b.cards.find? (·.id == id)

/-- Returns the cards in `column`, in order. -/
def cardsIn (b : Board) (column : Nat) : Array Card :=
  b.cards.filter (·.column == column)

/-- Returns the ID of the column `offset` places after `column`, where `offset` may be negative. -/
def columnAt (b : Board) (column : Nat) (offset : Int) : Option Nat := do
  let index ← b.columns.findIdx? (·.id == column)
  let target := (index : Int) + offset
  if target < 0 then none else (b.columns[target.toNat]?).map (·.id)

/-- Returns `b` with a new card at the end of `column`. -/
def addCard (b : Board) (column : Nat) (title : String) : Board :=
  { b with cards := b.cards.push { id := b.nextId, column, title }, nextId := b.nextId + 1 }

/-- Returns `b` with `f` applied to the card with the ID `id`. -/
def updateCard (b : Board) (id : Nat) (f : Card → Card) : Board :=
  { b with cards := b.cards.map fun c => if c.id == id then f c else c }

/-- Returns `b` without the card with the ID `id`. -/
def removeCard (b : Board) (id : Nat) : Board :=
  { b with cards := b.cards.filter (·.id != id) }

/--
Returns `b` with the card `id` moved into `column`, before the card `before`, or at the end of the
column if that is `none`.
-/
def moveCard (b : Board) (id column : Nat) (before : Option Nat) : Board :=
  match b.card? id with
  | none => b
  | some card =>
    if before == some id then
      b
    else
      let rest := (b.cards.filter (·.id != id)).toList
      let ahead (c : Card) := some c.id != before
      { b with
        cards := (rest.takeWhile ahead ++ { card with column } :: rest.dropWhile ahead).toArray }

/-- Returns `b` with a new column at the end. -/
def addColumn (b : Board) (name : String) : Board :=
  { b with columns := b.columns.push { id := b.nextId, name }, nextId := b.nextId + 1 }

/-- Returns `b` with the column `id` renamed. -/
def renameColumn (b : Board) (id : Nat) (name : String) : Board :=
  { b with columns := b.columns.map fun c => if c.id == id then { c with name } else c }

/-- Returns `b` without the column `id`, unless it has cards. -/
def removeColumn (b : Board) (id : Nat) : Board :=
  if b.cards.any (·.column == id) then b else { b with columns := b.columns.filter (·.id != id) }

/-- Returns `b` with the column `id` swapped with the one `offset` places after it, if any. -/
def shiftColumn (b : Board) (id : Nat) (offset : Int) : Board :=
  match b.columns.findIdx? (·.id == id), b.columnAt id offset with
  | some index, some other =>
    match b.columns.findIdx? (·.id == other) with
    | some otherIndex => { b with columns := b.columns.swapIfInBounds index otherIndex }
    | none => b
  | _, _ => b

/-- Moving a card leaves every other card on the board. -/
theorem mem_moveCard (b : Board) (id column : Nat) (before : Option Nat) (c : Card)
    (h : c ∈ b.cards) (hc : c.id ≠ id) : c ∈ (b.moveCard id column before).cards := by
  unfold moveCard
  split
  · exact h
  · split
    · exact h
    · have hr : c ∈ (b.cards.filter (·.id != id)).toList := by simp [h, hc]
      rw [← List.takeWhile_append_dropWhile (l := (b.cards.filter (·.id != id)).toList)
        (p := fun c => some c.id != before)] at hr
      simp only [List.mem_toArray, List.mem_append, List.mem_cons] at hr ⊢
      rcases hr with hr | hr
      · exact Or.inl hr
      · exact Or.inr (Or.inr hr)

/-- Removing a column never removes a card. -/
theorem cards_removeColumn (b : Board) (id : Nat) : (b.removeColumn id).cards = b.cards := by
  unfold removeColumn
  split <;> rfl

end Board
