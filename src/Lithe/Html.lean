module

/-!
The pure description of a page. Nothing here touches the DOM, so views can be evaluated, tested, and
reasoned about under native Lean as well as in a browser.
-/

@[expose] public section

namespace Lithe

/-- A snapshot of a DOM event, which handlers read without performing any effects. -/
structure Event where
  /-- The event's type, such as `click`. -/
  type : String := ""
  /-- The `value` of the event's target, or empty if it has none. -/
  value : String := ""
  /-- The `checked` state of the event's target, or `false` if it has none. -/
  checked : Bool := false
  /-- The event's `key`, or empty if it has none. -/
  key : String := ""
  /-- When the event happened, in milliseconds since the page started loading. -/
  timeStamp : Float := 0
  deriving Inhabited, Repr

/-- How to respond to an event. -/
structure Handler (Msg : Type) where
  /-- Returns the message for the event, or `none` to send no message. -/
  run : Event → Option Msg
  /-- Whether to cancel the event's default action, which applies even if `run` returns `none`. -/
  preventDefault : Bool := false
  /-- Whether to stop the event from reaching handlers on the element's ancestors. -/
  stopPropagation : Bool := false

/-- Returns `h` with the transformation `f` applied to its messages. -/
def Handler.map (f : α → β) (h : Handler α) : Handler β :=
  { h with run := fun e => (h.run e).map f }

/-- Returns `h`, also canceling the event's default action. -/
def Handler.withPreventDefault (h : Handler Msg) : Handler Msg :=
  { h with preventDefault := true }

/-- Returns `h`, also stopping the event from reaching handlers on the element's ancestors. -/
def Handler.withStopPropagation (h : Handler Msg) : Handler Msg :=
  { h with stopPropagation := true }

/-- The value of an attribute. -/
inductive AttrValue where
  /-- The attribute has this text. -/
  | str (s : String)
  /-- The attribute is present with no text if `true`, and absent if `false`. -/
  | bool (b : Bool)
  /-- The attribute is absent. -/
  | absent
  deriving BEq, Inhabited, Repr

/-- The representation of `ElementHandle`. -/
opaque ElementHandle.Pointed : NonemptyType

/-- A DOM element, which only code that runs in the browser can inspect. -/
def ElementHandle : Type := ElementHandle.Pointed.type

instance : Nonempty ElementHandle := ElementHandle.Pointed.property

/--
Imperative code that runs once after its element is added to the page. The action it returns runs
when the element is removed.
-/
abbrev Action := ElementHandle → IO (IO Unit)

/-- Something that can be set on an element. -/
inductive Attr (Msg : Type) where
  /-- An attribute or, for those that track user input such as `value`, a property. -/
  | value (name : String) (value : AttrValue)
  /-- A handler for events of the type `event`. -/
  | on (event : String) (handler : Handler Msg)
  /-- An action, which runs once regardless of later changes to it. -/
  | use (action : Action)

instance : Inhabited (Attr Msg) := ⟨.value "" .absent⟩

/-- Returns `a` with the transformation `f` applied to its messages. -/
def Attr.map (f : α → β) : Attr α → Attr β
  | .value name v => .value name v
  | .on event handler => .on event (handler.map f)
  | .use action => .use action

/--
The static part of some markup, which a macro computes at compile time. Each instance is a clone of
`html`, which must have one root element, and `paths` locates the target of each hole of the
instance, as the child indices to follow from the root.
-/
structure Template where
  /-- The markup, in which a comment marks where the content of each child hole goes. -/
  html : String
  /-- The path from the root to the target of each hole. -/
  paths : Array (Array Nat)
  /-- Identifies the template: two templates with the same key are interchangeable. -/
  key : String
  deriving Inhabited

mutual

/-- A description of some DOM nodes, which can send messages of type `Msg` to the app. -/
inductive Html (Msg : Type) where
  /-- No nodes. -/
  | empty
  /-- A text node. -/
  | text (s : String)
  /-- An element built at run time, for trees that aren't known at compile time. -/
  | elem (tag : String) (attrs : Array (Attr Msg)) (children : Array (Html Msg))
  /-- A list whose items keep their DOM nodes and state as they move, identified by unique keys. -/
  | keyed (items : Array (String × Html Msg))
  /-- An instance of a template, with one hole for each of its paths. -/
  | template (template : Template) (holes : Array (Hole Msg))

/-- The dynamic content of a template. -/
inductive Hole (Msg : Type) where
  /-- Content to place before the comment at the hole's path. -/
  | child (html : Html Msg)
  /-- Something to set on the element at the hole's path. -/
  | attr (attr : Attr Msg)

end

instance : Inhabited (Html Msg) := ⟨.empty⟩
instance : Inhabited (Hole Msg) := ⟨.child .empty⟩

mutual

/-- Returns `h` with the transformation `f` applied to its messages. -/
partial def Html.map (f : α → β) : Html α → Html β
  | .empty => .empty
  | .text s => .text s
  | .elem tag attrs children => .elem tag (attrs.map (·.map f)) (children.map (Html.map f))
  | .keyed items => .keyed (items.map fun (k, h) => (k, h.map f))
  | .template t holes => .template t (holes.map (Hole.map f))

/-- Returns `h` with the transformation `f` applied to its messages. -/
partial def Hole.map (f : α → β) : Hole α → Hole β
  | .child h => .child (h.map f)
  | .attr a => .attr (a.map f)

end

namespace Html

/-- Returns a keyed list of `view` applied to each of `xs`, identified by `key`. -/
def forEach [ToString κ] (xs : Array α) (key : α → κ) (view : α → Html Msg) : Html Msg :=
  .keyed (xs.map fun x => (toString (key x), view x))

mutual

/-- Returns a description of `h` for debugging. -/
partial def debug : Html Msg → String
  | .empty => "empty"
  | .text s => s!"text({s})"
  | .elem tag _ children => s!"<{tag}>[{", ".intercalate (children.map debug).toList}]"
  | .keyed items => s!"keyed[{", ".intercalate (items.map fun (k, h) => s!"{k}: {debug h}").toList}]"
  | .template t holes => s!"«{t.html}»[{", ".intercalate (holes.map debugHole).toList}]"

/-- Returns a description of `h` for debugging. -/
partial def debugHole : Hole Msg → String
  | .child h => debug h
  | .attr (.value name v) => s!"{name}={repr v}"
  | .attr (.on event _) => s!"on{event}"
  | .attr (.use _) => "use"

end

end Html

/-- Values that can be the content of a hole in markup. -/
class ToChild (α : Type) (Msg : Type) where
  /-- Converts `a` to the content of a hole. -/
  toChild (a : α) : Html Msg

/--
Lets elements in a hole take their message type from the enclosing markup, which is not yet known
when instance resolution first runs.
-/
@[default_instance] instance : ToChild (Html Msg) Msg := ⟨id⟩
instance : ToChild String Msg := ⟨.text⟩
instance : ToChild Nat Msg := ⟨(.text <| toString ·)⟩
instance : ToChild Int Msg := ⟨(.text <| toString ·)⟩
instance : ToChild Float Msg := ⟨(.text <| toString ·)⟩
instance : ToChild Char Msg := ⟨(.text <| toString ·)⟩

/-- Converts `none` to no content. -/
instance [ToChild α Msg] : ToChild (Option α) Msg where
  toChild
    | some a => ToChild.toChild a
    | none => .empty

/-- Values that can be the value of an attribute in markup. -/
class ToAttrValue (α : Type) where
  /-- Converts `a` to the value of an attribute. -/
  toAttrValue (a : α) : AttrValue

instance : ToAttrValue AttrValue := ⟨id⟩
instance : ToAttrValue String := ⟨.str⟩
instance : ToAttrValue Bool := ⟨.bool⟩
instance : ToAttrValue Nat := ⟨(.str <| toString ·)⟩
instance : ToAttrValue Int := ⟨(.str <| toString ·)⟩
instance : ToAttrValue Float := ⟨(.str <| toString ·)⟩

/-- Converts `none` to an absent attribute. -/
instance [ToAttrValue α] : ToAttrValue (Option α) where
  toAttrValue
    | some a => ToAttrValue.toAttrValue a
    | none => .absent

/-- Joins the nonempty tokens with spaces, for attributes such as `class`. -/
instance : ToAttrValue (Array String) where
  toAttrValue tokens := .str (" ".intercalate (tokens.filter (!·.isEmpty)).toList)

/-- Returns the class `name` if `on` is `true`, and otherwise an empty token. -/
def cls (name : String) (on : Bool) : String :=
  if on then name else ""

/-- Values that can respond to events in markup. -/
class ToHandler (α : Type) (Msg : Type) where
  /-- Converts `a` to a handler. -/
  toHandler (a : α) : Handler Msg

/-- Sends the message for every event, and lets the message type determine the type of `a`. -/
@[default_instance] instance : ToHandler Msg Msg := ⟨fun m => { run := fun _ => some m }⟩
instance : ToHandler (Handler Msg) Msg := ⟨id⟩
/-- Sends the message for the event. -/
instance : ToHandler (Event → Msg) Msg := ⟨fun f => { run := (some <| f ·) }⟩
/-- Sends the message for the event, if any. -/
instance : ToHandler (Event → Option Msg) Msg := ⟨fun f => { run := f }⟩
/-- Sends the message for the `value` of the event's target. -/
instance : ToHandler (String → Msg) Msg := ⟨fun f => { run := fun e => some (f e.value) }⟩
/-- Sends the message for the `checked` state of the event's target. -/
instance : ToHandler (Bool → Msg) Msg := ⟨fun f => { run := fun e => some (f e.checked) }⟩

/-- Returns the handler for `a`, also canceling the event's default action. -/
def preventDefault [ToHandler α Msg] (a : α) : Handler Msg :=
  (ToHandler.toHandler a).withPreventDefault

/-- Returns the handler for `a`, also stopping the event from reaching the element's ancestors. -/
def stopPropagation [ToHandler α Msg] (a : α) : Handler Msg :=
  (ToHandler.toHandler a).withStopPropagation

end Lithe
