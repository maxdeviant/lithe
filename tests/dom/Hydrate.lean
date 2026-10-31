import LitheTest.Util

open Lithe LitheTest
open Js.Dom
open Std.Async

/-! Checks that adopting the rendering of a description leaves what mounting it leaves. -/

abbrev Gen := StateM StdGen

def nat (bound : Nat) : Gen Nat :=
  modifyGet fun g => randNat g 0 (bound - 1)

def word : Gen String := do
  return #["", "a", "b", "long text", "<&>", "é日本 😀", "a\r\nb", "  ", "\n"][← nat 9]!

def attrs : Gen (Array (Attr Nat)) := do
  let mut result := #[]
  if (← nat 2) == 0 then
    result := result.push (.value "class" (.str (← word)))
  if (← nat 3) == 0 then
    result := result.push (.value "title" (if (← nat 2) == 0 then .absent else .bool true))
  if (← nat 3) == 0 then
    result := result.push (.on "click" { run := fun _ => some 0 })
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
  match ← nat (if depth == 0 then 2 else 9) with
  | 0 => return .empty
  | 1 => return .text (← word)
  | 2 =>
    let tag := #["div", "span", "ul", "pre", "section"][← nat 5]!
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
  | 5 =>
    let a ← html (depth - 1)
    let b ← html (depth - 1)
    let w ← word
    return <div>static {a} middle {b}{w} end</div>
  | 6 =>
    let value ← word
    let on ← nat 2
    let text ← word
    return (
      <form>
        <input value={value} />
        <input type="checkbox" checked={on == 0} />
        <textarea value={text}>old</textarea>
        <select value={"b"}><option value="a">A</option><option value="b">B</option></select>
        <noscript><p>no</p></noscript>
      </form>)
  | 7 =>
    let width ← nat 9
    let a ← html 0
    return (
      <svg viewBox="0 0 1 1">
        <rect width={width} />
        <text>t{a}</text>
        <foreignObject><div>{width}</div></foreignObject>
      </svg>)
  | _ =>
    let mut items := #[]
    for k in ← keys do
      items := items.push (toString k, ← html (depth - 1))
    return .keyed items

def handlerCount (rt : Runtime Nat) : IO Nat := do
  return (← rt.handlers.get).fold (fun n _ entries => n + entries.size) 0

/-- Returns whether `root` still has all of the elements it had when `markElements` last ran. -/
@[extern js inline
  "(#1.__marked.every((e) => #1.contains(e)) && #1.querySelectorAll('*').length === #1.__marked.length) ? 1 : 0"]
opaque elementsKept (root : @& JsValue) : BaseIO Bool

@[extern js inline "(#1.__marked = [...#1.querySelectorAll('*')], 0)"]
opaque markElements (root : @& JsValue) : BaseIO Unit

/--
Returns every node in `root`, including comments and how text is divided, with the live properties
of elements rather than the attributes that only set their initial state.
-/
@[extern js inline
  "$rt.mkString(((root) => { const live = ['value', 'checked', 'selected']; const go = (n) => { if (n.nodeType === 3) return 'T(' + n.data + ')'; if (n.nodeType === 8) return 'C'; const props = live.filter((p) => p in n).map((p) => p + ':' + n[p]).join(','); const named = [...n.attributes].filter((a) => !live.includes(a.name)).map((a) => a.name + '=' + a.value).sort().join(' '); const inner = n.localName === 'noscript' || n.localName === 'textarea' ? '' : [...n.childNodes].map(go).join(''); return '<' + n.namespaceURI + ' ' + n.localName + ' ' + props + ' ' + named + '>' + inner + '</>'; }; return [...root.childNodes].map(go).join(''); })(#1))"]
opaque exactDom (root : @& JsValue) : BaseIO String

/-- Returns a root with the HTML that `html` is the rendering of. -/
def rendered (html : String) : IO Element := do
  let root ← newRoot
  root.val.set "innerHTML" (.ofString html)
  return root

/-- Checks whether adopting `shown` as `wanted` replaces it, and that it leaves what mounting leaves. -/
def replaces (name : String) (shown wanted : Html Nat) (expected := true) : IO Unit := do
  let root ← rendered shown.render
  let rt : Runtime Nat ← Runtime.new root.val fun _ => pure ()
  let (_, replaced) ← rt.hydrateRoot root.val wanted
  checkEq name replaced expected
  let fresh ← newRoot
  let freshRt : Runtime Nat ← Runtime.new fresh.val fun _ => pure ()
  discard <| freshRt.mount fresh.val .null wanted
  checkEq s!"{name}, which leaves the same page" (← exactDom root.val) (← exactDom fresh.val)
  root.remove
  fresh.remove

def randomDescriptions : IO Unit := do
  let mut gen := mkStdGen 7
  let mut mismatches := 0
  let mut replacements := 0
  let mut lostElements := 0
  let mut patchFailures := 0
  let iterations := 1500
  for i in [0:iterations] do
    let (view, g) := (html 4).run gen
    let (next, g) := (html 4).run g
    gen := g
    let fresh ← newRoot
    let freshRt : Runtime Nat ← Runtime.new fresh.val fun _ => pure ()
    let freshMounted ← freshRt.mount fresh.val .null view
    let root ← rendered view.render
    markElements root.val
    let rt : Runtime Nat ← Runtime.new root.val fun _ => pure ()
    let (mounted, replaced) ← rt.hydrateRoot root.val view
    if replaced then
      replacements := replacements + 1
      IO.println s!"FAIL iteration {i} was replaced\n  html: {view.render}"
    unless ← elementsKept root.val do
      lostElements := lostElements + 1
    let actual ← exactDom root.val
    let expected ← exactDom fresh.val
    if actual != expected || (← handlerCount rt) != (← handlerCount freshRt) then
      mismatches := mismatches + 1
      if mismatches ≤ 3 then
        IO.println s!"FAIL iteration {i}\n  html:     {view.render}\n  expected: {expected}\n  actual:   {actual}"
    let patched ← rt.patch root.val .null mounted next
    let freshPatched ← freshRt.patch fresh.val .null freshMounted next
    if (← exactDom root.val) != (← exactDom fresh.val) then
      patchFailures := patchFailures + 1
      if patchFailures ≤ 3 then
        IO.println s!"FAIL iteration {i}: patching\n  expected: {← exactDom fresh.val}\n  actual:   {← exactDom root.val}"
    rt.unmount patched
    freshRt.unmount freshPatched
    if (← handlerCount rt) != 0 then
      IO.println s!"FAIL iteration {i}: unmounting left handlers"
    root.remove
    fresh.remove
  checkEq s!"adopting matches mounting in {iterations} random descriptions" mismatches 0
  checkEq "adopting replaces nothing" replacements 0
  checkEq "adopting keeps the elements" lostElements 0
  checkEq "adopted pages patch like mounted ones" patchFailures 0

def wrongPages : IO Unit := do
  replaces "different text" (<p>{"a"}</p>) (<p>{"b"}</p>)
  replaces "different static text" (<p>a{"x"}</p>) (<p>b{"x"}</p>)
  replaces "a different element" (.elem "div" #[] #[]) (.elem "span" #[] #[])
  replaces "a different template" (<p>{"x"}</p>) (<div>{"x"}</div>)
  replaces "an extra node" (<div>{"a"}</div>) (<div></div>)
  replaces "a missing node" (<div></div>) (<div>{Html.elem "b" #[] #[]}</div>)
  replaces "an extra node at the root" (.keyed #[("a", .elem "p" #[] #[]), ("b", .elem "p" #[] #[])])
    (.elem "p" #[] #[])
  replaces "a hole that the parser restructures" (<p>{Html.elem "div" #[] #[]}</p>)
    (<p>{Html.elem "div" #[] #[]}</p>)
  replaces "text in a table that the parser moves" (.elem "table" #[] #[.text "x"])
    (.elem "table" #[] #[.text "x"])
  replaces "a NUL, which the parser turns into something else" (.text "a\x00b") (.text "a\x00b")
  replaces "a different attribute, which is corrected" (<p title={"a"}>x</p>) (<p title={"b"}>x</p>) false
  replaces "an attribute that's gone, which is removed" (<p title={"a"}>x</p>) (<p title={none (α := String)}>x</p>) false
  -- Handlers from before something was found to be wrong must not stay.
  let shown : Html Nat := <div><b onclick={(1 : Nat)}>a</b>{"x"}</div>
  let wanted : Html Nat := <div><b onclick={(1 : Nat)}>a</b>{"y"}</div>
  let root ← rendered shown.render
  let rt : Runtime Nat ← Runtime.new root.val fun _ => pure ()
  discard <| rt.hydrateRoot root.val wanted
  checkEq "replacing leaves only the new handlers" (← handlerCount rt) 1
  root.remove

def edgeCases : IO Unit := do
  let view : Html Nat := <main><p>{"x"}</p></main>
  -- A client on its own has nothing to adopt, which isn't a mismatch.
  replaces "an empty root" .empty view false
  let spaced ← rendered s!"\n    {view.render}\n  "
  let rt : Runtime Nat ← Runtime.new spaced.val fun _ => pure ()
  markElements spaced.val
  let (_, replaced) ← rt.hydrateRoot spaced.val view
  check "whitespace around the page isn't a mismatch" !replaced
  check "and keeps the elements" (← elementsKept spaced.val)
  spaced.remove
  let textFirst : Html Nat := .keyed #[("a", .text "  x"), ("b", .elem "p" #[] #[])]
  let textRoot ← rendered s!"{textFirst.render}\n"
  let textRt : Runtime Nat ← Runtime.new textRoot.val fun _ => pure ()
  let (_, replaced) ← textRt.hydrateRoot textRoot.val textFirst
  check "whitespace that the view describes is kept" !replaced
  checkEq "and is still there" (← (textRoot.val.get "textContent") >>= fromJs) "  x"
  textRoot.remove
  let elementFirst : Html Nat := .keyed #[("a", .empty), ("b", .elem "p" #[] #[]), ("c", .text "x")]
  let elementRoot ← rendered s!"\n  {elementFirst.render}"
  let elementRt : Runtime Nat ← Runtime.new elementRoot.val fun _ => pure ()
  let (_, replaced) ← elementRt.hydrateRoot elementRoot.val elementFirst
  check "text later in a list doesn't count as text at the start" !replaced
  elementRoot.remove
  let blank ← rendered "\n  "
  let blankRt : Runtime Nat ← Runtime.new blank.val fun _ => pure ()
  let (_, replaced) ← blankRt.hydrateRoot blank.val view
  check "a root with only whitespace counts as empty" !replaced
  checkEq "and gets the page" (← (← find blank "p").textContent) "x"
  blank.remove

  -- Some parsers split long text, which `elementsKept` can't see, as it only looks at elements.
  let long := String.ofList (List.replicate 200000 'x')
  let longView : Html Nat := <p>a{long}b</p>
  let longRoot ← rendered longView.render
  let longRt : Runtime Nat ← Runtime.new longRoot.val fun _ => pure ()
  let (_, replaced) ← longRt.hydrateRoot longRoot.val longView
  check "long text is adopted" !replaced
  longRoot.remove

  let raw : Html Nat := .elem "div" #[] #[
    .elem "style" #[] #[.text "a > b { content: '</x'; }"],
    .elem "script" #[.value "type" (.str "text/plain")] #[.text "a<b && c </script"],
    .elem "title" #[] #[.text "<t>&"],
    .elem "textarea" #[.value "value" (.str "\nv")] #[],
    .elem "textarea" #[] #[.text "kept"],
    .elem "noscript" #[] #[.elem "p" #[] #[.text "n"]],
    .elem "svg" #[] #[.elem "linearGradient" #[] #[], .elem "style" #[] #[.text "<x>"]]]
  replaces "raw text and elements like it" raw raw false

def running : IO Unit := do
  let actions ← IO.mkRef (0 : Nat)
  let count : Action := fun _ => do
    actions.modify (· + 1)
    return pure ()
  let view (n : Nat) : Html (Nat → Nat) :=
    <div>
      <button id="inc" onclick={(· + 1)} use={count}>{n}</button>
      <input id="field" value={toString n} />
    </div>
  let root ← rendered (view 5).render
  markElements root.val
  (← find root "#field").cast HtmlInputElement >>= (·.setValue "typed")
  (App.simple 5 view).hydrate root
  check "starting keeps the page" (← elementsKept root.val)
  checkEq "actions run when starting" (← actions.get) 1
  let field ← (← find root "#field").cast HtmlInputElement
  checkEq "the model wins over what's in a field" (← field.value) "5"
  (← find root "#inc").click
  discard <| EAsync.toBaseIO do
    settle
    checkEq "handlers work" (← (← find root "#inc").textContent) "6"
    checkEq "the field follows the model" (← field.value) "6"
    check "updating keeps the page" (← elementsKept root.val)
    checkEq "actions don't run again" (← actions.get) 1
    root.remove

    let missing : Option Nat ← readJsonScript? "lithe-none"
    check "a missing element is `none`" missing.isNone
    IO.println "finished"

structure Data where
  count : Nat
  title : String
  deriving ToJson, FromJs, BEq

def dataScripts : IO Unit := do
  let data : Data := { count := 3, title := "é</script><b>x<!--" }
  let holder ← rendered (jsonScript "lithe-data" data)
  checkEq "a script's content has no markup in it" (← holder.val.get "children" >>= (·.get "length") >>= fromJs) (1 : Nat)
  let read : Option Data ← readJsonScript? "lithe-data"
  check "what `jsonScript` writes can be read" (read == some data)
  holder.remove
  let bad ← rendered "<script id=\"lithe-bad\" type=\"application/json\">{</script>"
  let result ← (readJsonScript? "lithe-bad" : IO (Option Nat)).toBaseIO
  check "what isn't JSON is an error" (match result with | .error _ => true | .ok _ => false)
  bad.remove

def main : IO Unit := do
  randomDescriptions
  wrongPages
  edgeCases
  dataScripts
  running
