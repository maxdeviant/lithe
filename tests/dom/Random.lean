import LitheTest.Util

open Lithe LitheTest
open Js.Dom

/-!
Checks that patching from any description to any other leaves the same DOM and handlers as mounting
the new description from scratch.
-/

abbrev Gen := StateM StdGen

def nat (bound : Nat) : Gen Nat :=
  modifyGet fun g => randNat g 0 (bound - 1)

def word : Gen String := do
  return #["", "a", "b", "long text", "<&>"][← nat 5]!

def attrs : Gen (Array (Attr Nat)) := do
  let mut result := #[]
  if (← nat 2) == 0 then
    result := result.push (.value "class" (.str (← word)))
  if (← nat 3) == 0 then
    result := result.push (.value "title" (if (← nat 2) == 0 then .absent else .bool true))
  if (← nat 3) == 0 then
    result := result.push (.on "click" { run := fun _ => some 0 })
  if (← nat 3) == 0 then
    result := result.push (.on "input" { run := fun _ => some 1 })
  return result

/-- Returns a random permutation of a random subset of the numbers below 8. -/
def keys : Gen (Array Nat) := do
  let mut pool := Array.range 8
  let mut result := #[]
  for _ in [0:← nat 8] do
    let i ← nat pool.size
    result := result.push pool[i]!
    pool := pool.eraseIdx! i
  return result

partial def html (depth : Nat) : Gen (Html Nat) := do
  let kind ← nat (if depth == 0 then 2 else 6)
  match kind with
  | 0 => return .empty
  | 1 => return .text (← word)
  | 2 =>
    let tag := #["div", "span", "ul"][← nat 3]!
    let mut children := #[]
    for _ in [0:← nat 4] do
      children := children.push (← html (depth - 1))
    return .elem tag (← attrs) children
  | 3 =>
    let a ← html (depth - 1)
    let b ← html (depth - 1)
    let c ← word
    let n ← nat 3
    return <div class={c}>{a}<span data-static="yes">text</span>{b}<b onclick={n}>{n}</b></div>
  | 4 =>
    let a ← html (depth - 1)
    let t ← nat 2
    return <section title={if t == 0 then some "t" else none}>{a}</section>
  | _ =>
    let mut items := #[]
    for k in ← keys do
      items := items.push (toString k, ← html (depth - 1))
    return .keyed items

/-- Returns how many handlers are in the table. -/
def handlerCount (rt : Runtime Nat) : IO Nat := do
  return (← rt.handlers.get).fold (fun n _ entries => n + entries.size) 0

def main : IO Unit := do
  let root ← newRoot
  let rt : Runtime Nat ← Runtime.new root.val fun _ => pure ()
  let mut gen := mkStdGen 42
  let mut mounted : Mounted Nat := .empty
  let mut failures := 0
  let mut renderFailures := 0
  let iterations := 1500
  for i in [0:iterations] do
    let (next, g) := (html 4).run gen
    gen := g
    mounted ← rt.patch root.val .null mounted next
    rt.runActions
    let fresh ← newRoot
    let freshRt : Runtime Nat ← Runtime.new fresh.val fun _ => pure ()
    let freshMounted ← freshRt.mount fresh.val .null next
    let actual ← innerHtml root
    let expected ← innerHtml fresh
    let actualHandlers ← handlerCount rt
    let expectedHandlers ← handlerCount freshRt
    if actual != expected || actualHandlers != expectedHandlers then
      failures := failures + 1
      if failures ≤ 3 then
        IO.println s!"FAIL iteration {i}\n  expected: {expected} ({expectedHandlers} handlers)\n  actual:   {actual} ({actualHandlers} handlers)"
    let mountedDom ← describeDom fresh.val
    let renderedDom ← describeParsed next.render
    if mountedDom != renderedDom then
      renderFailures := renderFailures + 1
      if renderFailures ≤ 3 then
        IO.println s!"FAIL iteration {i}: rendering\n  mounted:  {mountedDom}\n  rendered: {renderedDom}\n  html:     {next.render}"
    freshRt.dispose freshMounted
    fresh.remove
    let remaining ← handlerCount freshRt
    if remaining != 0 then
      IO.println s!"FAIL iteration {i}: disposing left {remaining} handlers"
  checkEq s!"patching matches mounting in {iterations} random updates" failures 0
  checkEq s!"rendering matches mounting for {iterations} random descriptions" renderFailures 0
  rt.unmount mounted
  checkEq "unmounting leaves no handlers" (← handlerCount rt) 0
  checkEq "unmounting leaves no nodes" (← innerHtml root) ""
  IO.println "finished"
