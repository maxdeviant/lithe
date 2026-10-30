import LitheTest.Util

open Lithe LitheTest
open Js.Dom
open Std.Async

/-! Checks that keyed lists keep their elements, and move as few of them as they can. -/

inductive Msg where
  | set (items : Array Nat)
  | picked (item seen : Nat)

structure Model where
  items : Array Nat
  /-- The last item picked, and the size of the list it saw when rendering. -/
  picked : Nat × Nat := (0, 0)

def update : Msg → Model → Model × Cmd Msg
  | .set items, m => ({ m with items }, .none)
  | .picked item seen, m => ({ m with picked := (item, seen) }, .none)

def parseItems (e : Lithe.Event) : Msg :=
  .set ((e.value.splitOn ",").toArray.filterMap (·.toNat?))

def view (m : Model) : Html Msg :=
  <div>
    <ul>
      {Html.forEach m.items id fun i =>
        <li id={s!"i{i}"} onclick={Msg.picked i m.items.size}><input />{i}</li>}
    </ul>
    <button id="go" onclick={parseItems}>go</button>
    <p id="picked">{s!"{m.picked.1} {m.picked.2}"}</p>
  </div>

/-- Returns an observer of the changes to the children of `node`, which counts the nodes involved. -/
@[extern js inline
  "(() => { const o = new MutationObserver((r) => { for (const x of r) o.count += x.addedNodes.length + x.removedNodes.length; }); o.count = 0; o.observe(#1, { childList: true }); return o; })()"]
opaque observe (node : @& JsValue) : BaseIO JsValue

/-- Returns how many nodes were inserted or removed since the last call. -/
@[extern js inline "(() => { const n = #1.count; #1.count = 0; return n; })()"]
opaque changes (observer : @& JsValue) : BaseIO Nat

def texts (root : Element) : IO String := do
  let items ← root.querySelectorAll "li"
  return " ".intercalate (← items.mapM (·.textContent)).toList

def run : Async Unit := do
  let host ← newRoot
  let app : App Model Msg := { init := ({ items := #[1, 2, 3, 4, 5, 6] }, .none), update, view }
  app.mount host
  let setItems (items : Array Nat) : Async Unit := do
    -- The handler reads its target's `value`, so the button carries the new list.
    let go ← find host "#go"
    go.val.set "value" (.ofString (",".intercalate (items.map toString).toList))
    go.click
    settle
  let ul ← find host "ul"
  let observer ← observe ul.val
  let elementFor (i : Nat) : IO JsValue := return (← find host s!"#i{i}").val
  let first ← elementFor 1
  let sixth ← elementFor 6
  let input ← (← find host "#i3 input").cast HtmlInputElement
  input.setValue "typed"

  setItems #[6, 2, 3, 4, 5, 1]
  checkEq "items are in the new order" (← texts host) "6 2 3 4 5 1"
  check "moved items keep their elements" (JsValue.strictEq (← elementFor 1) first)
  check "moved items keep their elements" (JsValue.strictEq (← elementFor 6) sixth)
  -- Each of the two moved items is one removal and one insertion.
  checkEq "a swap moves only the two items" (← changes observer) 4
  checkEq "state outside the model survives moves"
    (← (← (← find host "#i3 input").cast HtmlInputElement).value) "typed"

  setItems #[6, 2, 3, 4, 5, 1]
  checkEq "no changes touch nothing" (← changes observer) 0

  setItems #[1, 5, 4, 3, 2, 6]
  checkEq "items can reverse" (← texts host) "1 5 4 3 2 6"

  setItems #[1, 5, 7, 3, 8, 6]
  checkEq "items can come and go at once" (← texts host) "1 5 7 3 8 6"
  check "kept items keep their elements" (JsValue.strictEq (← elementFor 1) first)

  setItems #[]
  checkEq "the list can empty" (← texts host) ""
  checkEq "the comment that anchors the list stays" (← innerHtml ul) "<!---->"
  setItems #[9, 10]
  checkEq "the list can refill" (← texts host) "9 10"

  -- Handlers see the values of the latest render, not of the one that created their element.
  setItems #[9, 10, 11]
  (← find host "#i9").click
  settle
  checkEq "handlers are up to date" (← (← find host "#picked").textContent) "9 3"

  setItems #[9, 9, 10]
  checkEq "duplicate keys still render every item" (← texts host) "9 9 10"
  setItems #[10, 9]
  checkEq "the list recovers from duplicate keys" (← texts host) "10 9"

def main : IO Unit := do
  discard <| EAsync.toBaseIO do
    try
      run
      IO.println "finished"
    catch e =>
      IO.println s!"FAIL threw: {e}"
