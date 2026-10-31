import Js
import Lithe.Html
import Std.Data.HashMap
import Std.Data.HashSet

/-!
Keeps the DOM in step with `Html`: mounting creates the nodes for a description, and patching updates
them to match a new one, keeping as many nodes as it can.

Elements with handlers don't get JS listeners of their own, as each JS function makes everything it
captures persistent, and rendering would create one for every handler. Instead, one listener on the
root finds handlers in a table that only Lean touches.
-/

namespace Lithe

/-!
Direct DOM operations. Unlike `Js.Dom` they skip checking the types of what they're given, so they
are only for values that this module has obtained itself, and they cost less on the patching path.
-/

namespace Raw

@[extern js inline "document.createTextNode(#1.toString())"]
opaque createText (s : @& String) : BaseIO JsValue

/-- Creates an element to go in `parent`, in the SVG namespace if that's what `parent` leads to. -/
@[extern js inline
  "((parent, tag) => { const svg = 'http://www.w3.org/2000/svg'; return tag === 'svg' || (parent.namespaceURI === svg && parent.localName !== 'foreignObject') ? document.createElementNS(svg, tag) : document.createElement(tag); })(#1, #2.toString())"]
opaque createElementIn (parent : @& JsValue) (tag : @& String) : BaseIO JsValue

/-- Parses `html` as a template, and returns its root element. -/
@[extern js inline
  "(() => { const t = document.createElement('template'); t.innerHTML = #1.toString(); return t.content.firstChild; })()"]
opaque parseTemplate (html : @& String) : BaseIO JsValue

/-- Parses `html` as a template whose root element is only recognized inside of `svg`. -/
@[extern js inline
  "(() => { const t = document.createElement('template'); t.innerHTML = `<svg>${#1.toString()}</svg>`; return t.content.firstChild.firstChild; })()"]
opaque parseSvgTemplate (html : @& String) : BaseIO JsValue

@[extern js inline "#1.cloneNode(true)"]
opaque clone (node : @& JsValue) : BaseIO JsValue

@[extern js inline "#1.childNodes[#2]"]
opaque childAt (node : @& JsValue) (index : @& Nat) : BaseIO JsValue

@[extern js inline "#1.parentNode"]
opaque parentNode (node : @& JsValue) : BaseIO JsValue

@[extern js inline "(#1.insertBefore(#2, #3), 0)"]
opaque insertBefore (parent child ref : @& JsValue) : BaseIO Unit

@[extern js inline "(#1.remove(), 0)"]
opaque remove (node : @& JsValue) : BaseIO Unit

@[extern js inline "(#1.replaceChildren(), 0)"]
opaque clearChildren (node : @& JsValue) : BaseIO Unit

@[extern js inline "(#1.data = #2.toString(), 0)"]
opaque setData (node : @& JsValue) (s : @& String) : BaseIO Unit

@[extern js inline "(#1.setAttribute(#2.toString(), #3.toString()), 0)"]
opaque setAttribute (el : @& JsValue) (name value : @& String) : BaseIO Unit

@[extern js inline "(#1.removeAttribute(#2.toString()), 0)"]
opaque removeAttribute (el : @& JsValue) (name : @& String) : BaseIO Unit

@[extern js inline "$rt.mkString(String(#1[#2.toString()] ?? ''))"]
opaque getStringProperty (el : @& JsValue) (name : @& String) : BaseIO String

@[extern js inline "(#1[#2.toString()] = #3.toString(), 0)"]
opaque setStringProperty (el : @& JsValue) (name value : @& String) : BaseIO Unit

@[extern js inline "#1[#2.toString()] === true ? 1 : 0"]
opaque getBoolProperty (el : @& JsValue) (name : @& String) : BaseIO Bool

@[extern js inline "(#1[#2.toString()] = #3 !== 0, 0)"]
opaque setBoolProperty (el : @& JsValue) (name : @& String) (value : Bool) : BaseIO Unit

/-- Returns the handler slot of `el`, or 0 if it has none. -/
@[extern js inline "#1.__litheSlot ?? 0"]
opaque getSlot (el : @& JsValue) : BaseIO Nat

@[extern js inline "(#1.__litheSlot = #2, 0)"]
opaque setSlot (el : @& JsValue) (slot : @& Nat) : BaseIO Unit

@[extern js inline "(#1.addEventListener(#2.toString(), #3, #4 !== 0), 0)"]
opaque addEventListener (target : @& JsValue) (type : @& String) (listener : @& JsValue)
    (capture : Bool) : BaseIO Unit

@[extern js inline "(#1.removeEventListener(#2.toString(), #3), 0)"]
opaque removeEventListener (target : @& JsValue) (type : @& String) (listener : @& JsValue) :
    BaseIO Unit

@[extern js inline "#1.target"]
opaque eventTarget (e : @& JsValue) : BaseIO JsValue

@[extern js inline "$rt.mkString(#1.type)"]
opaque eventType (e : @& JsValue) : BaseIO String

@[extern js inline "$rt.mkString(String(#1.target?.value ?? ''))"]
opaque eventValue (e : @& JsValue) : BaseIO String

@[extern js inline "#1.target?.checked === true ? 1 : 0"]
opaque eventChecked (e : @& JsValue) : BaseIO Bool

@[extern js inline "$rt.mkString(String(#1.key ?? ''))"]
opaque eventKey (e : @& JsValue) : BaseIO String

@[extern js inline "#1.timeStamp ?? 0"]
opaque eventTimeStamp (e : @& JsValue) : BaseIO Float

@[extern js inline "#1[#2.toString()] === true ? 1 : 0"]
opaque eventFlag (e : @& JsValue) (name : @& String) : BaseIO Bool

-- SVG elements keep the case of their tag names, unlike HTML elements.
@[extern js inline "$rt.mkString(String(#1.target?.tagName ?? '').toUpperCase())"]
opaque eventTargetTag (e : @& JsValue) : BaseIO String

@[extern js inline "(#1.preventDefault(), 0)"]
opaque preventDefault (e : @& JsValue) : BaseIO Unit

@[extern js inline "(#1.stopPropagation(), 0)"]
opaque stopPropagation (e : @& JsValue) : BaseIO Unit

/-- Returns the same object, as an element reaches actions as an opaque handle. -/
@[extern js inline "#1"]
opaque toHandle (el : @& JsValue) : ElementHandle

/-- Returns whether `a` and `b` are the same object. -/
@[extern js inline "#1 === #2 ? 1 : 0"]
opaque sameTemplate (a b : @& Template) : Bool

end Raw

/-- Returns the DOM element behind `h`. -/
@[extern js inline "#1"]
opaque ElementHandle.toElement (h : @& ElementHandle) : Js.Dom.HtmlElement

/-- Returns the snapshot of the DOM event `e`. -/
def Event.ofJs (e : JsValue) : IO Event := do
  return {
    type := ← Raw.eventType e
    value := ← Raw.eventValue e
    checked := ← Raw.eventChecked e
    key := ← Raw.eventKey e
    timeStamp := ← Raw.eventTimeStamp e
    ctrlKey := ← Raw.eventFlag e "ctrlKey"
    metaKey := ← Raw.eventFlag e "metaKey"
    shiftKey := ← Raw.eventFlag e "shiftKey"
    altKey := ← Raw.eventFlag e "altKey"
    targetTag := ← Raw.eventTargetTag e
  }

/-- What is on an element, which mirrors `Attr`. -/
inductive MountedAttr (Msg : Type) where
  | value (name : String) (value : AttrValue)
  /-- The handler for `event`, which is in the table under `slot`. -/
  | on (event : String) (slot : Nat) (handler : IO.Ref (Handler Msg))
  /-- An action, with what to run to clean up after it. -/
  | use (cleanup : IO.Ref (IO Unit))

instance : Inhabited (MountedAttr Msg) := ⟨.value "" .absent⟩

mutual

/-- The DOM nodes for some `Html`, and what patching needs to know about them. -/
inductive Mounted (Msg : Type) where
  | empty
  | text (node : JsValue) (s : String)
  | elem (node : JsValue) (tag : String) (attrs : Array (MountedAttr Msg))
      (children : Array (Mounted Msg))
  | keyed (items : Array (String × Mounted Msg))
  | template (node : JsValue) (template : Template) (holes : Array (MountedHole Msg))

/-- The DOM nodes for a `Hole`. -/
inductive MountedHole (Msg : Type) where
  /-- Content, which is placed before the comment `marker`. -/
  | child (marker : JsValue) (content : Mounted Msg)
  /-- Something set on the element `el`. -/
  | attr (el : JsValue) (attr : MountedAttr Msg)

end

instance : Inhabited (Mounted Msg) := ⟨.empty⟩

namespace Mounted

/-- Appends the outermost DOM nodes of `m` to `acc`, in document order. -/
partial def collectNodes (m : Mounted Msg) (acc : Array JsValue) : Array JsValue :=
  match m with
  | .empty => acc
  | .text node _ | .elem node .. | .template node .. => acc.push node
  | .keyed items => items.foldl (fun acc (_, item) => item.collectNodes acc) acc

/-- Returns the first of the outermost DOM nodes of `m`, if it has any. -/
partial def firstNode? : Mounted Msg → Option JsValue
  | .empty => none
  | .text node _ | .elem node .. | .template node .. => some node
  | .keyed items => items.findSome? fun (_, item) => item.firstNode?

end Mounted

/-- The events that don't bubble, which the root sees during the capture phase instead. -/
def captureEvents : Std.HashSet String :=
  Std.HashSet.ofList
    ["abort", "beforetoggle", "blur", "cancel", "canplay", "canplaythrough", "close", "cuechange",
      "durationchange", "emptied", "ended", "error", "focus", "invalid", "load", "loadeddata",
      "loadedmetadata", "loadstart", "mouseenter", "mouseleave", "pause", "play", "playing",
      "pointerenter", "pointerleave", "progress", "ratechange", "scroll", "scrollend", "seeked",
      "seeking", "stalled", "suspend", "timeupdate", "toggle", "volumechange", "waiting"]

/-- The properties to write instead of attributes, as attributes only set their initial state. -/
def isLiveProperty (name : String) : Bool :=
  name == "value" || name == "checked" || name == "selected" || name == "indeterminate"
    || name == "muted"

/-- The handlers on each element with any, which is identified by its slot. -/
abbrev HandlerTable (Msg : Type) := Std.HashMap Nat (Array (String × IO.Ref (Handler Msg)))

/-- Sets the attribute or property `name` of `el` to `value`. -/
def writeValue (el : JsValue) (name : String) (value : AttrValue) : IO Unit := do
  if isLiveProperty name then
    match value with
    | .str s =>
      -- Comparing to the live value avoids moving the cursor of an input that already has `s`.
      if (← Raw.getStringProperty el name) != s then
        Raw.setStringProperty el name s
    | .bool b =>
      if (← Raw.getBoolProperty el name) != b then
        Raw.setBoolProperty el name b
    | .absent =>
      if name == "value" then
        if (← Raw.getStringProperty el name) != "" then
          Raw.setStringProperty el name ""
      else if ← Raw.getBoolProperty el name then
        Raw.setBoolProperty el name false
  else
    match value with
    | .str s => Raw.setAttribute el name s
    | .bool true => Raw.setAttribute el name ""
    | .bool false | .absent => Raw.removeAttribute el name

/-- What mounting and patching share. -/
structure Runtime (Msg : Type) where
  /-- The root element, which holds the listeners. -/
  root : JsValue
  /-- The handlers on each element. -/
  handlers : IO.Ref (HandlerTable Msg)
  /-- The most recently used slot. -/
  lastSlot : IO.Ref Nat
  /-- The parsed templates, by key. -/
  templates : IO.Ref (Std.HashMap String JsValue)
  /-- The types of event that the root is listening for. -/
  listening : IO.Ref (Std.HashSet String)
  /-- The actions of the elements mounted since the last call to `runActions`. -/
  actions : IO.Ref (Array (IO Unit))
  /-- The listener for events that bubble. -/
  bubbleListener : JsValue
  /-- The listener for events that don't bubble. -/
  captureListener : JsValue

/--
Sends the message of each handler for the event `e`, walking up from its target through the
ancestors below `root`, or stopping at the target if `targetOnly`.
-/
def handleEvent (handlers : IO.Ref (HandlerTable Msg)) (dispatch : Msg → IO Unit) (root : JsValue)
    (targetOnly : Bool) (e : JsValue) : IO Unit := do
  let event ← Event.ofJs e
  let type := event.type
  let mut node ← Raw.eventTarget e
  while !node.isNull && !node.isUndefined && !(JsValue.strictEq node root) do
    let slot ← Raw.getSlot node
    if slot != 0 then
      let entries := (← handlers.get).getD slot #[]
      if let some (_, cell) := entries.find? (·.1 == type) then
        let handler ← cell.get
        if handler.preventDefault then
          Raw.preventDefault e
        if handler.stopPropagation then
          Raw.stopPropagation e
        if let some msg := handler.run event then
          dispatch msg
        if handler.stopPropagation then
          return
    if targetOnly then
      return
    node ← Raw.parentNode node

/-- Returns a runtime for rendering into `root`, which sends the messages of handlers to `dispatch`. -/
def Runtime.new (root : JsValue) (dispatch : Msg → IO Unit) : IO (Runtime Msg) := do
  let handlers ← IO.mkRef {}
  let bubble : JsValue → IO Unit := handleEvent handlers dispatch root false
  let capture : JsValue → IO Unit := handleEvent handlers dispatch root true
  return {
    root
    handlers
    lastSlot := ← IO.mkRef 0
    templates := ← IO.mkRef {}
    listening := ← IO.mkRef {}
    actions := ← IO.mkRef #[]
    bubbleListener := ← toJs bubble
    captureListener := ← toJs capture
  }

namespace Runtime

variable (rt : Runtime Msg)

/-- Runs the actions of the elements mounted since the last call, now that they are in the page. -/
def runActions : IO Unit := do
  for action in ← rt.actions.swap #[] do
    action

/-- Starts listening for events of the type `type` at the root, if it isn't already. -/
def listen (type : String) : IO Unit := do
  unless (← rt.listening.get).contains type do
    rt.listening.modify (·.insert type)
    if captureEvents.contains type then
      Raw.addEventListener rt.root type rt.captureListener true
    else
      Raw.addEventListener rt.root type rt.bubbleListener false

/-- Returns the slot of `el`, assigning it one if it has none. -/
def slotOf (el : JsValue) : IO Nat := do
  let slot ← Raw.getSlot el
  if slot != 0 then
    return slot
  let slot ← rt.lastSlot.modifyGet fun n => (n + 1, n + 1)
  Raw.setSlot el slot
  return slot

/-- Returns the parsed form of the template `t`. -/
def templateRoot (t : Template) : IO JsValue := do
  if let some root := (← rt.templates.get)[t.key]? then
    return root
  let root ← if t.svg then Raw.parseSvgTemplate t.html else Raw.parseTemplate t.html
  rt.templates.modify (·.insert t.key root)
  return root

/-- Sets `attr` on `el`. -/
def mountAttr (el : JsValue) : Attr Msg → IO (MountedAttr Msg)
  | .value name value => do
    writeValue el name value
    return .value name value
  | .on event handler => do
    rt.listen event
    let slot ← rt.slotOf el
    let cell ← IO.mkRef handler
    rt.handlers.modify fun table =>
      table.insert slot ((table.getD slot #[]).push (event, cell))
    return .on event slot cell
  | .use action => do
    let cleanup ← IO.mkRef (pure () : IO Unit)
    rt.actions.modify (·.push do cleanup.set (← action (Raw.toHandle el)))
    return .use cleanup

/-- Removes `attr` from `el`. -/
def removeAttr (el : JsValue) : MountedAttr Msg → IO Unit
  | .value name _ => writeValue el name .absent
  | .on event slot _ =>
    rt.handlers.modify fun table =>
      table.insert slot ((table.getD slot #[]).filter (·.1 != event))
  | .use cleanup => do (← cleanup.get)

/-- Updates `old` on `el` to `new`. -/
def patchAttr (el : JsValue) : MountedAttr Msg → Attr Msg → IO (MountedAttr Msg)
  | .value oldName oldValue, .value name value => do
    if oldName != name then
      writeValue el oldName .absent
      writeValue el name value
    else if isLiveProperty name || oldValue != value then
      -- Live properties are always checked, as the user may have changed them.
      writeValue el name value
    return .value name value
  | old@(.on oldEvent _ cell), .on event handler => do
    if oldEvent == event then
      cell.set handler
      return old
    rt.removeAttr el old
    rt.mountAttr el (.on event handler)
  | old@(.use _), .use _ => return old
  | old, new => do
    rt.removeAttr el old
    rt.mountAttr el new

/-- Forgets what `attr` added to the runtime, and runs its cleanup. -/
def disposeAttr : MountedAttr Msg → IO Unit
  | .value .. => pure ()
  | .on _ slot _ => rt.handlers.modify (·.erase slot)
  | .use cleanup => do (← cleanup.get)

end Runtime

/-- Reports that `key` occurs more than once in a keyed list. -/
def warnDuplicateKey (key : String) : IO Unit :=
  IO.eprintln s!"Lithe: the key `{key}` occurs more than once in a keyed list"

/-- Returns the node at `path` from `root`. -/
def resolvePath (root : JsValue) (path : Array Nat) : IO JsValue :=
  path.foldlM (init := root) fun node i => Raw.childAt node i

/-- Identifies what an `Attr` at the position `i` sets, for matching old attributes to new ones. -/
def attrIdentity : Attr Msg → Nat → String
  | .value name _, _ => s!"v:{name}"
  | .on event _, _ => s!"e:{event}"
  | .use _, i => s!"u:{i}"

/-- Identifies what a `MountedAttr` at the position `i` sets. -/
def mountedAttrIdentity : MountedAttr Msg → Nat → String
  | .value name _, _ => s!"v:{name}"
  | .on event .., _ => s!"e:{event}"
  | .use _, i => s!"u:{i}"

/--
Returns which items of `sources` are in a longest strictly increasing subsequence of the known
values, which are the items that don't need to move relative to each other.
-/
def longestIncreasing (sources : Array (Option Nat)) : Array Bool := Id.run do
  -- The index in `sources` of the smallest last item of an increasing subsequence of each length.
  let mut tails : Array Nat := #[]
  let mut previous : Array (Option Nat) := Array.replicate sources.size none
  for h : i in [:sources.size] do
    let some value := sources[i] | continue
    let mut low := 0
    let mut high := tails.size
    while low < high do
      let mid := (low + high) / 2
      if (sources[tails[mid]!]!).getD 0 < value then
        low := mid + 1
      else
        high := mid
    if low > 0 then
      previous := previous.set! i (some tails[low - 1]!)
    tails := if low == tails.size then tails.push i else tails.set! low i
  let mut keep := Array.replicate sources.size false
  let mut current := tails.back?
  while true do
    let some i := current | break
    keep := keep.set! i true
    current := previous[i]!
  return keep

namespace Runtime

variable (rt : Runtime Msg)

/-- Moves the outermost DOM nodes of `m` to before `ref`. -/
def moveBefore (parent ref : JsValue) (m : Mounted Msg) : BaseIO Unit := do
  for node in m.collectNodes #[] do
    Raw.insertBefore parent node ref

mutual

/-- Forgets everything `m` added to the runtime, and runs its cleanups. -/
partial def dispose : Mounted Msg → IO Unit
  | .empty | .text .. => pure ()
  | .elem _ _ attrs children => do
    for attr in attrs do
      rt.disposeAttr attr
    for child in children do
      dispose child
  | .keyed items => do
    for (_, item) in items do
      dispose item
  | .template _ _ holes => do
    for hole in holes do
      match hole with
      | .child _ content => dispose content
      | .attr _ attr => rt.disposeAttr attr

end

/-- Removes `m` from the page, and forgets everything it added to the runtime. -/
def unmount (m : Mounted Msg) : IO Unit := do
  rt.dispose m
  for node in m.collectNodes #[] do
    Raw.remove node

mutual

/-- Creates the DOM nodes for `h`, and inserts them into `parent` before `ref`. -/
partial def mount (parent ref : JsValue) : Html Msg → IO (Mounted Msg)
  | .empty => return .empty
  | .text s => do
    let node ← Raw.createText s
    Raw.insertBefore parent node ref
    return .text node s
  | .elem tag attrs children => do
    let node ← Raw.createElementIn parent tag
    let children ← children.mapM (mount node .null)
    -- Content comes first, so that `value` on a `select` is set after its options exist.
    let attrs ← attrs.mapM (rt.mountAttr node)
    Raw.insertBefore parent node ref
    return .elem node tag attrs children
  | .keyed items => do
    let mut seen : Std.HashSet String := {}
    let mut mounted := Array.emptyWithCapacity items.size
    for (key, item) in items do
      if seen.contains key then
        warnDuplicateKey key
      seen := seen.insert key
      mounted := mounted.push (key, ← mount parent ref item)
    return .keyed mounted
  | .template t holes => do
    let node ← Raw.clone (← rt.templateRoot t)
    -- Mounting content adds nodes, so the paths have to be followed first.
    let targets ← t.paths.mapM (resolvePath node)
    let mut mounted := Array.emptyWithCapacity holes.size
    for hole in holes, target in targets do
      mounted := mounted.push (← mountHole target hole)
    Raw.insertBefore parent node ref
    return .template node t mounted

/-- Fills the hole whose path leads to `target`. -/
partial def mountHole (target : JsValue) : Hole Msg → IO (MountedHole Msg)
  | .child h => do
    return .child target (← mount (← Raw.parentNode target) target h)
  | .attr attr => do
    return .attr target (← rt.mountAttr target attr)

/-- Updates `old` to match `new`, where `ref` is the DOM node that follows it in `parent`. -/
partial def patch (parent ref : JsValue) (old : Mounted Msg) (new : Html Msg) : IO (Mounted Msg) := do
  match old, new with
  | .empty, .empty => return .empty
  | .text node oldText, .text s =>
    if oldText != s then
      Raw.setData node s
    return .text node s
  | .elem node oldTag oldAttrs oldChildren, .elem tag attrs children =>
    if oldTag != tag then
      replace parent ref old new
    else
      let children ← patchChildren node oldChildren children
      let attrs ← patchAttrs node oldAttrs attrs
      return .elem node tag attrs children
  | .keyed olds, .keyed items => return .keyed (← patchKeyed parent ref olds items)
  | .template node oldTemplate oldHoles, .template t holes =>
    if Raw.sameTemplate oldTemplate t || oldTemplate.key == t.key then
      let mut mounted := Array.emptyWithCapacity holes.size
      for oldHole in oldHoles, hole in holes do
        mounted := mounted.push (← patchHole oldHole hole)
      return .template node oldTemplate mounted
    else
      replace parent ref old new
  | _, _ => replace parent ref old new

/-- Replaces `old` with new nodes for `new`. -/
partial def replace (parent ref : JsValue) (old : Mounted Msg) (new : Html Msg) :
    IO (Mounted Msg) := do
  let mounted ← mount parent ref new
  rt.unmount old
  return mounted

/-- Updates the hole `old` to match `new`. -/
partial def patchHole : MountedHole Msg → Hole Msg → IO (MountedHole Msg)
  | .child marker old, .child new => do
    return .child marker (← patch (← Raw.parentNode marker) marker old new)
  | .attr el old, .attr new => do
    return .attr el (← rt.patchAttr el old new)
  | old, _ => return old

/-- Updates the attributes of `el` from `olds` to `news`, matching them by what they set. -/
partial def patchAttrs (el : JsValue) (olds : Array (MountedAttr Msg)) (news : Array (Attr Msg)) :
    IO (Array (MountedAttr Msg)) := do
  let oldIds := olds.mapIdx fun i a => mountedAttrIdentity a i
  let newIds := news.mapIdx fun i a => attrIdentity a i
  for old in olds, id in oldIds do
    unless newIds.contains id do
      rt.removeAttr el old
  let mut mounted := Array.emptyWithCapacity news.size
  for new in news, id in newIds do
    match oldIds.idxOf? id with
    | some i => mounted := mounted.push (← rt.patchAttr el olds[i]! new)
    | none => mounted := mounted.push (← rt.mountAttr el new)
  return mounted

/--
Updates the children of `parent` by position. It works backward, so that the node to insert before
is always known.
-/
partial def patchChildren (parent : JsValue) (olds : Array (Mounted Msg)) (news : Array (Html Msg)) :
    IO (Array (Mounted Msg)) := do
  for i in [news.size:olds.size] do
    rt.unmount olds[i]!
  let mut ref := JsValue.null
  let mut reversed := Array.emptyWithCapacity news.size
  for i in [:news.size] do
    let index := news.size - 1 - i
    let child ← if h : index < olds.size then
        patch parent ref olds[index] news[index]!
      else
        mount parent ref news[index]!
    ref := child.firstNode?.getD ref
    reversed := reversed.push child
  return reversed.reverse

/-- Updates the items of a keyed list, moving as few as it can, given the node that follows them. -/
partial def patchKeyed (parent ref : JsValue) (olds : Array (String × Mounted Msg))
    (news : Array (String × Html Msg)) : IO (Array (String × Mounted Msg)) := do
  let sameKeys := olds.size == news.size &&
    (Array.zipWith (fun (a : String × Mounted Msg) (b : String × Html Msg) => a.1 == b.1) olds news).all id
  let mut sources : Array (Option Nat) := Array.emptyWithCapacity news.size
  if sameKeys then
    sources := Array.ofFn (n := news.size) fun i => some i.val
  else
    let mut oldIndex : Std.HashMap String Nat := {}
    for (key, _) in olds, i in [:olds.size] do
      oldIndex := oldIndex.insert key i
    let mut seen : Std.HashSet String := {}
    for (key, _) in news do
      if seen.contains key then
        warnDuplicateKey key
        sources := sources.push none
      else
        sources := sources.push oldIndex[key]?
      seen := seen.insert key
    let reused := sources.foldl (fun acc s => match s with
      | some i => acc.insert i
      | none => acc) ({} : Std.HashSet Nat)
    for (_, old) in olds, i in [:olds.size] do
      unless reused.contains i do
        rt.unmount old
  let keep := if sameKeys then Array.replicate news.size true else longestIncreasing sources
  let mut next := ref
  let mut reversed := Array.emptyWithCapacity news.size
  for i in [:news.size] do
    let index := news.size - 1 - i
    let (key, item) := news[index]!
    let mounted ← match sources[index]! with
      | some source => do
        let patched ← patch parent next olds[source]!.2 item
        unless keep[index]! do
          moveBefore parent next patched
        pure patched
      | none => mount parent next item
    next := mounted.firstNode?.getD next
    reversed := reversed.push (key, mounted)
  return reversed.reverse

end

end Runtime

end Lithe
