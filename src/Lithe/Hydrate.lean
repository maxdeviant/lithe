import Lithe.Dom

/-!
Adopts a page that `Html.render` wrote, so that a client can make it live without replacing it, which
would lose its focus, scroll positions, and anything else that isn't in the description.

The HTML has no markers for it to go by. The description says what each node has to be, so the only
thing the page can't show directly is where text from different places was merged, and that's found
by the length of the text that's expected.
-/

namespace Lithe

namespace Raw

@[extern js inline "document.createComment('')"]
opaque createMarker : BaseIO JsValue

@[extern js inline "#1.firstChild"]
opaque firstChild (node : @& JsValue) : BaseIO JsValue

@[extern js inline "#1.nextSibling"]
opaque nextSibling (node : @& JsValue) : BaseIO JsValue

/-- Joins adjacent text in `node`, as parsers may split long text into several nodes. -/
@[extern js inline "(#1.normalize(), 0)"]
opaque normalize (node : @& JsValue) : BaseIO Unit

/-- Removes `node` if it's text that is only whitespace, and returns whether there's nothing after. -/
@[extern js inline
  "((node) => { if (node === null) return 1; if (node.nodeType !== 3 || node.data.trim() !== '') return 0; const last = node.nextSibling === null; node.remove(); return last ? 1 : 0; })(#1)"]
opaque removeIfBlank (node : @& JsValue) : BaseIO Bool

@[extern js inline "#1.childNodes.length"]
opaque childCount (node : @& JsValue) : BaseIO Nat

@[extern js inline "#1.nodeType"]
opaque nodeType (node : @& JsValue) : BaseIO Nat

@[extern js inline "$rt.mkString(#1.data)"]
opaque nodeData (node : @& JsValue) : BaseIO String

@[extern js inline "$rt.mkString(#1.localName)"]
opaque localName (node : @& JsValue) : BaseIO String

/-- Returns whether `node` is an element named `tag`, as HTML elements have their names lowercased. -/
@[extern js inline
  "(#1 !== null && #1.nodeType === 1 && #1.localName.toLowerCase() === #2.toString().toLowerCase()) ? 1 : 0"]
opaque isElementNamed (node : @& JsValue) (tag : @& String) : BaseIO Bool

/--
Returns the text node `node` if it starts with `s`, with the rest split off into a node of its own,
and otherwise null. In the elements whose content `Html.render` can't escape, it looks for what that
wrote for `s`, and gives the node the text `s`.
-/
@[extern js inline
  "((node, s, parent) => { if (node === null || node.nodeType !== 3) return null; const raw = ['iframe', 'noembed', 'noframes', 'plaintext', 'script', 'style', 'xmp'].includes(parent.localName); const text = raw ? s.replaceAll('</', '<\\\\/') : s; if (!node.data.startsWith(text)) return null; if (node.data.length > text.length) node.splitText(text.length); if (raw) node.data = s; return node; })(#1, #2.toString(), #3)"]
opaque claimText (node : @& JsValue) (s : @& String) (parent : @& JsValue) : BaseIO JsValue

/-- Sets an attribute unless it already has this value, as setting `src` again restarts loading. -/
@[extern js inline
  "(#1.getAttribute(#2.toString()) === #3.toString() ? 0 : (#1.setAttribute(#2.toString(), #3.toString()), 0))"]
opaque syncAttribute (el : @& JsValue) (name value : @& String) : BaseIO Unit

/-- Replaces the children of `el` with copies of those of `source`. -/
@[extern js inline "(#1.replaceChildren(...[...#2.childNodes].map((c) => c.cloneNode(true))), 0)"]
opaque copyChildren (el source : @& JsValue) : BaseIO Unit

/-- Returns the text of the element with the ID `id`, or null if there is none. -/
@[extern js inline "(document.getElementById(#1.toString())?.textContent ?? null)"]
opaque elementText (id : @& String) : BaseIO JsValue

/-- Returns the value that the JS string `text` is the JSON of, or undefined if it isn't JSON. -/
@[extern js inline "(() => { try { return JSON.parse(#1); } catch { return undefined; } })()"]
opaque parseJson (text : @& JsValue) : BaseIO JsValue

end Raw

/-- Returns whether the first node that `h` has in a page is text, or `none` if it has no nodes there. -/
partial def Html.startsWithText? : Html Msg → Option Bool
  | .empty | .text "" => none
  | .text _ => some true
  | .keyed items => items.findSome? (·.2.startsWithText?)
  | .elem .. | .template .. => some false

/-- What adopting the nodes of a template has to do, which is computed once per template. -/
inductive Plan where
  /-- Static text. -/
  | text (s : String)
  /-- A place for content, for the hole with this index. -/
  | content (index : Nat)
  /-- A static element, with the indices of the holes that set something on it. -/
  | elem (tag : String) (holes : Array Nat) (children : Array Plan)
  /-- A static `textarea`, whose content in the page is its value, so that it comes from `source`. -/
  | textarea (holes : Array Nat) (source : JsValue)
  /-- A static `noscript`, whose content is only text in the page, as scripts are enabled there. -/
  | noscript (holes : Array Nat)
  deriving Inhabited

/-- Returns the plan for `node` in a template with holes at `paths`, where `path` leads to `node`. -/
partial def Plan.ofNode (paths : Array (Array Nat)) (node : JsValue) (path : Array Nat) : IO Plan := do
  let holes := (Array.range paths.size).filter (paths[·]! == path)
  match ← Raw.nodeType node with
  | 3 => return .text (← Raw.nodeData node)
  | 8 => return .content holes[0]!
  | _ =>
    match ← Raw.localName node with
    | "textarea" => return .textarea holes node
    | "noscript" => return .noscript holes
    | tag =>
      let mut children := #[]
      for i in [0:← Raw.childCount node] do
        children := children.push (← Plan.ofNode paths (← Raw.childAt node i) (path.push i))
      return .elem tag holes children

namespace Runtime

variable (rt : Runtime Msg)

/-- Sets `attr` on `el`, which already has what the server rendered, if the page is as expected. -/
def hydrateAttr (el : JsValue) : Attr Msg → IO (MountedAttr Msg)
  | .value name value => do
    if isLiveProperty name then
      writeValue el name value
    else
      match value with
      | .str s => Raw.syncAttribute el name s
      | .bool true => Raw.syncAttribute el name ""
      | .bool false | .absent => Raw.removeAttribute el name
    return .value name value
  | attr => rt.mountAttr el attr

/-- Returns the node for the text `s` at `cursor`, and throws an error if that's not what's there. -/
def adoptText (parent cursor : JsValue) (s : String) : IO JsValue := do
  let node ← Raw.claimText cursor s parent
  if node.isNull then
    throw (.userError s!"expected the text `{s}`")
  return node

mutual

/--
Adopts the nodes for `h` in `parent`, starting from `cursor`. Returns what's mounted, and the node
after it. Throws an error if the page isn't what `h` describes.
-/
partial def hydrate (plans : IO.Ref (Std.HashMap String Plan)) (parent cursor : JsValue) :
    Html Msg → IO (Mounted Msg × JsValue)
  | .empty => return (.empty, cursor)
  | .text "" => do
    -- Mounting makes a node for empty text, which the page can't have, and patching expects one.
    let node ← Raw.createText ""
    Raw.insertBefore parent node cursor
    return (.text node "", cursor)
  | .text s => do
    let node ← adoptText parent cursor s
    return (.text node s, ← Raw.nextSibling node)
  | .elem tag attrs children => do
    unless ← Raw.isElementNamed cursor tag do
      throw (.userError s!"expected the element `{tag}`")
    let mut next ← Raw.firstChild cursor
    let mut mounted := Array.emptyWithCapacity children.size
    if tag == "textarea" || tag == "noscript" then
      -- What's in the page for these isn't made of the children, so they get new nodes.
      Raw.clearChildren cursor
      next := .null
      mounted ← children.mapM (rt.mount cursor .null)
    else
      for child in children do
        let (m, after) ← hydrate plans cursor next child
        mounted := mounted.push m
        next := after
    unless next.isNull do
      throw (.userError s!"more nodes than expected in `{tag}`")
    let attrs ← attrs.mapM (rt.hydrateAttr cursor)
    return (.elem cursor tag attrs mounted, ← Raw.nextSibling cursor)
  | .keyed items => do
    let mut next := cursor
    let mut mounted := Array.emptyWithCapacity items.size
    for (key, item) in items do
      let (m, after) ← hydrate plans parent next item
      mounted := mounted.push (key, m)
      next := after
    return (.keyed mounted, next)
  | .template t holes => do
    let plan ← match (← plans.get)[t.key]? with
      | some plan => pure plan
      | none => do
        let plan ← Plan.ofNode t.paths (← rt.templateRoot t) #[]
        plans.modify (·.insert t.key plan)
        pure plan
    let out ← IO.mkRef (Array.replicate holes.size (none : Option (MountedHole Msg)))
    let next ← hydratePlan plans holes out parent cursor plan
    let mut mounted := Array.emptyWithCapacity holes.size
    for hole in ← out.get do
      let some hole := hole | throw (.userError "a hole with nowhere to go")
      mounted := mounted.push hole
    return (.template cursor t mounted, next)

/-- Adopts the nodes for a part of a template, and returns the node after them. -/
partial def hydratePlan (plans : IO.Ref (Std.HashMap String Plan)) (holes : Array (Hole Msg))
    (out : IO.Ref (Array (Option (MountedHole Msg)))) (parent cursor : JsValue) :
    Plan → IO JsValue
  | .text s => do Raw.nextSibling (← adoptText parent cursor s)
  | .content i => do
    let .child h := holes[i]! | throw (.userError "a place for content with a hole that isn't")
    let (content, next) ← hydrate plans parent cursor h
    let marker ← Raw.createMarker
    Raw.insertBefore parent marker next
    out.modify (·.set! i (some (.child marker content)))
    return next
  | .elem tag attrHoles children => do
    unless ← Raw.isElementNamed cursor tag do
      throw (.userError s!"expected the element `{tag}`")
    let mut next ← Raw.firstChild cursor
    for child in children do
      next ← hydratePlan plans holes out cursor next child
    unless next.isNull do
      throw (.userError s!"more nodes than expected in `{tag}`")
    hydrateAttrHoles holes out cursor attrHoles
    Raw.nextSibling cursor
  | .textarea attrHoles source => do
    unless ← Raw.isElementNamed cursor "textarea" do
      throw (.userError "expected the element `textarea`")
    Raw.copyChildren cursor source
    hydrateAttrHoles holes out cursor attrHoles
    Raw.nextSibling cursor
  | .noscript attrHoles => do
    unless ← Raw.isElementNamed cursor "noscript" do
      throw (.userError "expected the element `noscript`")
    hydrateAttrHoles holes out cursor attrHoles
    Raw.nextSibling cursor

/-- Sets what the holes `attrHoles` have on `el`. -/
partial def hydrateAttrHoles (holes : Array (Hole Msg))
    (out : IO.Ref (Array (Option (MountedHole Msg)))) (el : JsValue) (attrHoles : Array Nat) :
    IO Unit := do
  for i in attrHoles do
    let .attr attr := holes[i]! | throw (.userError "an element with a hole that isn't for it")
    out.modify (·.set! i (some (.attr el (← rt.hydrateAttr el attr))))

end

/--
Adopts what's in `root` as what `h` describes, keeping its nodes. If it's something else, this reports
that and replaces it. An empty `root` has `h` mounted in it, as there's nothing to adopt. Whitespace
at either end that `h` doesn't describe is ignored, as it comes from the formatting of a page. Returns
what's mounted, and whether something had to be replaced.
-/
def hydrateRoot (root : JsValue) (h : Html Msg) : IO (Mounted Msg × Bool) := do
  Raw.normalize root
  unless h.startsWithText? == some true do
    discard <| Raw.removeIfBlank (← Raw.firstChild root)
  if (← Raw.childCount root) == 0 then
    return (← rt.mount root .null h, false)
  try
    let (mounted, rest) ← rt.hydrate (← IO.mkRef {}) root (← Raw.firstChild root) h
    unless ← Raw.removeIfBlank rest do
      throw (.userError "more nodes than expected at the root")
    return (mounted, false)
  catch e =>
    IO.eprintln s!"Lithe: the page isn't what the view describes, so it was replaced: {e}"
    -- Nothing has run yet, and none of the nodes that the handlers are for are going to stay.
    rt.handlers.set {}
    rt.actions.set #[]
    Raw.clearChildren root
    return (← rt.mount root .null h, true)

end Runtime

/--
Returns the value in the element that `jsonScript` wrote with the ID `id`, or `none` if there's no
such element, and throws an error if its content can't be read as that type.
-/
def readJsonScript? [FromJs α] (id : String) : IO (Option α) := do
  let text ← Raw.elementText id
  if text.isNull then
    return none
  let value ← Raw.parseJson text
  if value.isUndefined then
    throw (.userError s!"the element with the ID {id} doesn't contain JSON")
  return some (← fromJs value)

end Lithe
