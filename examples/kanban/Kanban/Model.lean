import Lithe
import Kanban.Board
import Kanban.Browser
import Kanban.Route

open Lithe

/-! The state of the app, and the updates to it. -/

/-- Where a dragged card would land. -/
structure DropTarget where
  column : Nat
  /-- The card it would go before, or `none` for the end of the column. -/
  before : Option Nat
  deriving BEq

/-- The unsaved state of the open card. -/
structure Editor where
  id : Nat
  title : String
  description : String
  labels : Array Label
  column : Nat

/-- Returns the state for starting to edit `c`. -/
def Editor.ofCard (c : Card) : Editor :=
  { id := c.id, title := c.title, description := c.description, labels := c.labels, column := c.column }

/-- The number of past states of the board that can be restored. -/
def maxUndo : Nat := 100

/-- The state of the app. -/
structure Model where
  board : Board
  /-- The earlier states of the board, latest last. -/
  past : Array Board := #[]
  /-- The states of the board that were undone, latest undone last. -/
  future : Array Board := #[]
  /-- The open card, if any. -/
  editor : Option Editor := none
  /-- The column whose form for a new card is open. -/
  adding : Option Nat := none
  /-- The text of the new card. -/
  draft : String := ""
  /-- The text to look for in cards. -/
  search : String := ""
  /-- The only label to show cards with. -/
  labelFilter : Option Label := none
  /-- The ID of the card being dragged. -/
  dragging : Option Nat := none
  dropTarget : Option DropTarget := none
  /-- What went wrong most recently, for the user to read. -/
  problem : Option String := none

/-- The things that can happen. -/
inductive Msg where
  | addColumn
  | renameColumn (id : Nat) (name : String)
  | removeColumn (id : Nat)
  | shiftColumn (id : Nat) (offset : Int)
  | startAdding (column : Nat)
  | setDraft (text : String)
  | submitDraft
  | cancelAdding
  | moveCard (id column : Nat)
  | dragStart (id : Nat)
  | dragOver (target : Option DropTarget)
  | drop
  | dragEnd
  /-- The URL now says `route`. -/
  | routeChanged (route : Route)
  | closeEditor
  | setTitle (title : String)
  | setDescription (description : String)
  | setLabel (label : Label) (on : Bool)
  | setColumn (column : String)
  | saveEditor
  | deleteCard
  | setSearch (text : String)
  | toggleFilter (label : Label)
  | undo
  | redo
  | dismissProblem
  /-- An effect finished, where `action` says what it was doing in words that follow "Couldn't". -/
  | finished (action : String) (outcome : Except IO.Error Unit)

/-- Returns the effect of saving `board`. -/
def save (board : Board) : Cmd Msg :=
  .attempt (saveBoard board) (.finished "save the board")

/-- Returns the effect of going to `route`. -/
def navigate (route : Route) : Cmd Msg :=
  .attempt (setHash route.href) (.finished "change the URL")

namespace Model

/-- Returns the state with `board` as an undoable change, and the effect of saving it. -/
def commit (m : Model) (board : Board) : Model × Cmd Msg :=
  if board == m.board then
    (m, .none)
  else
    let past := if m.past.size < maxUndo then m.past else m.past.eraseIdxIfInBounds 0
    ({ m with board, past := past.push m.board, future := #[] }, save board)

/-- Returns the state and effects for arriving at `route`. -/
def goTo (m : Model) : Route → Model × Cmd Msg
  | .board => ({ m with editor := none }, .none)
  | .card id =>
    match m.board.card? id with
    | none => ({ m with editor := none }, navigate .board)
    | some card =>
      -- The draft is kept if this is the card that's already open.
      if (m.editor.map (·.id)) == some id then
        (m, .none)
      else
        ({ m with editor := some (Editor.ofCard card) }, .none)

/-- Returns `m` with `f` applied to the open card, if any. -/
def edit (m : Model) (f : Editor → Editor) : Model :=
  { m with editor := m.editor.map f }

/-- Returns the state and effects after saving the open card, which is `e`. -/
def saveCard (m : Model) (e : Editor) : Model × Cmd Msg :=
  let title := e.title.trimAscii.copy
  if title.isEmpty then
    (m, .none)
  else
    let moved :=
      if (m.board.card? e.id).map (·.column) == some e.column then
        m.board
      else
        m.board.moveCard e.id e.column none
    let board := moved.updateCard e.id fun c =>
      { c with title, description := e.description, labels := e.labels }
    let (m, saving) := m.commit board
    ({ m with editor := none }, .batch #[saving, navigate .board])

/-- Returns the state and effects after `msg`. -/
def update (m : Model) : Msg → Model × Cmd Msg
  | .addColumn => m.commit (m.board.addColumn "New column")
  | .renameColumn id name => m.commit (m.board.renameColumn id name)
  | .removeColumn id => m.commit (m.board.removeColumn id)
  | .shiftColumn id offset => m.commit (m.board.shiftColumn id offset)
  | .startAdding column => ({ m with adding := some column, draft := "" }, .none)
  | .setDraft text => ({ m with draft := text }, .none)
  | .submitDraft =>
    let title := m.draft.trimAscii.copy
    match m.adding with
    | some column =>
      if title.isEmpty then
        (m, .none)
      else
        { m with draft := "" }.commit (m.board.addCard column title)
    | none => (m, .none)
  | .cancelAdding => ({ m with adding := none, draft := "" }, .none)
  | .moveCard id column => m.commit (m.board.moveCard id column none)
  | .dragStart id => ({ m with dragging := some id, dropTarget := none }, .none)
  | .dragOver target =>
    -- Something from outside of the page, such as a file, isn't a card.
    (if m.dragging.isSome then { m with dropTarget := target } else m, .none)
  | .drop =>
    let cleared := { m with dragging := none, dropTarget := none }
    match m.dragging, m.dropTarget with
    | some id, some target => cleared.commit (m.board.moveCard id target.column target.before)
    | _, _ => (cleared, .none)
  | .dragEnd => ({ m with dragging := none, dropTarget := none }, .none)
  | .routeChanged route => m.goTo route
  | .closeEditor =>
    if m.editor.isSome then ({ m with editor := none }, navigate .board) else (m, .none)
  | .setTitle title => (m.edit ({ · with title }), .none)
  | .setDescription description => (m.edit ({ · with description }), .none)
  | .setLabel label on =>
    let without (labels : Array Label) := labels.filter (· != label)
    (m.edit fun e => { e with labels := if on then (without e.labels).push label else without e.labels }, .none)
  | .setColumn column =>
    (match column.toNat? with
      | some column => m.edit ({ · with column })
      | none => m, .none)
  | .saveEditor =>
    match m.editor with
    | some e => m.saveCard e
    | none => (m, .none)
  | .deleteCard =>
    match m.editor with
    | some e =>
      let (m, saving) := m.commit (m.board.removeCard e.id)
      ({ m with editor := none }, .batch #[saving, navigate .board])
    | none => (m, .none)
  | .setSearch text => ({ m with search := text }, .none)
  | .toggleFilter label =>
    ({ m with labelFilter := if m.labelFilter == some label then none else some label }, .none)
  | .undo =>
    match m.past.back? with
    | some board =>
      ({ m with board, past := m.past.pop, future := m.future.push m.board }, save board)
    | none => (m, .none)
  | .redo =>
    match m.future.back? with
    | some board =>
      ({ m with board, past := m.past.push m.board, future := m.future.pop }, save board)
    | none => (m, .none)
  | .dismissProblem => ({ m with problem := none }, .none)
  | .finished _ (.ok ()) => (m, .none)
  | .finished action (.error e) => ({ m with problem := some s!"Couldn't {action}: {e}" }, .none)

/-- Returns whether `card` should be shown, given the search and the label filter. -/
def shows (m : Model) (card : Card) : Bool :=
  let query := m.search.trimAscii.copy.toLower
  let matchesText (s : String) := (s.toLower.splitOn query).length > 1
  (query.isEmpty || matchesText card.title || matchesText card.description)
    && m.labelFilter.all card.labels.contains

end Model
