import Js
import Kanban.Board

/-! The parts of the browser that the app reads and writes: its storage, and the URL. -/

/-- The `localStorage` key of the saved board. -/
def storageKey : String := "lithe-kanban-board"

/-- Writes `board` to `localStorage`. -/
def saveBoard (board : Board) : IO Unit := do
  let json ← (← JsValue.getGlobal "JSON").callMethod "stringify" #[← toJs board]
  discard <| (← JsValue.getGlobal "localStorage").callMethod "setItem" #[.ofString storageKey, json]

/-- Returns the board in `localStorage`, or `none` if there is none. Throws an error if it's bad. -/
def loadBoard : IO (Option Board) := do
  let saved ← (← JsValue.getGlobal "localStorage").callMethod "getItem" #[.ofString storageKey]
  if saved.isNull then
    return none
  let board : Board ← fromJs (← (← JsValue.getGlobal "JSON").callMethod "parse" #[saved])
  unless board.isValid do
    throw (.userError "its cards and columns don't match up")
  return some board

/-- Returns the hash of the page's URL, including its `#`. -/
def currentHash : IO String := do
  fromJs (← (← JsValue.getGlobal "location").get "hash")

/-- Changes the hash of the page's URL, which adds an entry to the browser's history. -/
def setHash (hash : String) : IO Unit := do
  (← JsValue.getGlobal "location").set "hash" (.ofString hash)
