module

public import Lithe.Html

/-!
Renders `Html` to a string of HTML, which parses to the same page that mounting it builds, without
the handlers and actions, which have no form in HTML. Nothing here touches the DOM.
-/

public section

namespace Lithe

namespace Render

/-- The HTML elements that have no closing tag and no children. -/
def voidElements : List String :=
  ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]

/-- The HTML elements whose content the parser doesn't decode, so that it can't be escaped. -/
def rawTextElements : List String :=
  ["iframe", "noembed", "noframes", "plaintext", "script", "style", "xmp"]

/-- The HTML elements in which the parser drops a newline at the start of the content. -/
def newlineDroppingElements : List String := ["listing", "pre", "textarea"]

/-- Returns `s` with what's significant in HTML text replaced by entities. -/
def escapeText (s : String) : String :=
  (((s.replace "&" "&amp;").replace "<" "&lt;").replace ">" "&gt;")

/-- Returns `s` with what's significant in a quoted attribute value replaced by entities. -/
def escapeAttr (s : String) : String :=
  (escapeText s).replace "\"" "&quot;"

/--
Returns text for a raw text element, which can't escape what would end the element, and so breaks it
up instead. Otherwise text that isn't trusted could add markup to the page.
-/
def neutralizeRawText (s : String) : String :=
  s.replace "</" "<\\/"

/-- Returns whether `name` can be written as the name of a tag or attribute. -/
def isValidName (name : String) : Bool :=
  !name.isEmpty && name.toList.all fun c => !c.isWhitespace && !['"', '\'', '<', '>', '/', '='].contains c

/-- Returns the characters of the tag at the start of `cs`, up to its `>`, and those after it. -/
partial def splitTag (cs : List Char) (quoted := false) (tag : List Char := []) :
    List Char × List Char :=
  match cs with
  | [] => (tag.reverse, [])
  | '>' :: rest => if quoted then splitTag rest quoted ('>' :: tag) else (tag.reverse, rest)
  | '"' :: rest => splitTag rest (!quoted) ('"' :: tag)
  | c :: rest => splitTag rest quoted (c :: tag)

/-- Returns the text of the `value` attribute in the characters of a tag, if it has one. -/
partial def valueAttr (tag : List Char) (quoted := false) : Option String :=
  match tag with
  | [] => none
  | '"' :: rest => valueAttr rest (!quoted)
  | c :: rest =>
    if !quoted && " value=\"".toList.isPrefixOf (c :: rest) then
      some (String.ofList ((rest.drop 7).takeWhile (· != '"')))
    else
      valueAttr rest quoted

/-- Returns whether the characters of a tag are the opening tag of an `option`. -/
def isOptionTag (tag : List Char) : Bool :=
  tag == "option".toList || " ".toList.isPrefixOf (tag.drop 6) && "option".toList.isPrefixOf tag

/-- Returns the value that an `option` has from its text, given what follows its opening tag. -/
def optionText (rest : List Char) : String :=
  " ".intercalate (((String.ofList (rest.takeWhile (· != '<'))).split Char.isWhitespace).toList.map
    (·.toString) |>.filter (!·.isEmpty))

/--
Adds `selected` to the first `option` in `cs` with the value `value`, as the `select` around them has
no attribute for its value. `cs` is rendered markup, so that any `<` outside of a tag is the start of
a tag, as text has it escaped.
-/
partial def markSelected (value : String) (cs : List Char) (acc : List Char := []) : List Char :=
  match cs with
  | [] => acc.reverse
  | '<' :: rest =>
    let (tag, after) := splitTag rest
    let matches? := isOptionTag tag && match valueAttr tag with
      | some attr => attr == escapeAttr value
      | none => optionText after == escapeText value
    if matches? then
      acc.reverse ++ '<' :: tag ++ " selected>".toList ++ after
    else
      markSelected value after ('>' :: tag.reverse ++ '<' :: acc)
  | c :: rest => markSelected value rest (c :: acc)

/-- Appends `attr` to `out`, which is in an opening tag. -/
def renderAttr (out : String) : Attr Msg → String
  | .value name value =>
    -- This is the one live property that has no attribute.
    if name == "indeterminate" || !isValidName name then
      out
    else
      match value with
      | .str s => out ++ s!" {name}=\"{escapeAttr s}\""
      | .bool true => out ++ s!" {name}"
      | .bool false | .absent => out
  | .on .. | .use _ => out

/-- Returns the text that the attribute `.value "value" _` gives the property `value`. -/
def valueText : AttrValue → String
  | .str s => s
  | .bool _ | .absent => ""

/-- What to do at a position in the static HTML of a template. -/
inductive Step (Msg : Type) where
  /-- Replaces the marker with content, which is in SVG if `svg`. -/
  | child (html : Html Msg) (svg : Bool)
  | attr (attr : Attr Msg)
  /-- Replaces what's between here and `stop` with the value of a `textarea`. -/
  | textarea (value : String) (stop : Nat)
  /-- Marks the start of the content of a `select`. -/
  | selectStart
  /-- Selects the option with the value `value`, in the content since the start was marked. -/
  | selectEnd (value : String)

instance : Inhabited (Step Msg) := ⟨.selectStart⟩

/-- Returns the steps for a hole at `site`, each with its position in the template's HTML. -/
def stepsOf (site : Template.Site) (hole : Hole Msg) : Array (Nat × Step Msg) :=
  match site, hole with
  | .child pos svg, .child h => #[(pos, .child h svg)]
  | .attr pos, .attr a => #[(pos, .attr a)]
  | .textarea start stop, .attr (.value _ v) => #[(start, .textarea (valueText v) stop)]
  | .select start stop, .attr (.value _ v) => #[(start, .selectStart), (stop, .selectEnd (valueText v))]
  | _, _ => #[]

/-- Returns the part of `s` between two byte offsets. -/
def slice (s : String) (start stop : Nat) : String :=
  String.Pos.Raw.extract s ⟨start⟩ ⟨stop⟩

mutual

/--
Appends `h` to `out`. Its parent is in SVG if `svg`, and doesn't decode its content if `raw`.
-/
partial def renderTo (out : String) (svg raw : Bool) : Html Msg → String
  | .empty => out
  | .text s => out ++ (if raw then neutralizeRawText s else escapeText s)
  | .keyed items => items.foldl (fun out (_, h) => renderTo out svg raw h) out
  | .elem tag attrs children => renderElem out svg tag attrs children
  | .template t holes => renderTemplate out t holes

/-- Appends an element to `out`, or nothing if `tag` can't be written, as the DOM wouldn't accept it. -/
partial def renderElem (out : String) (parentSvg : Bool) (tag : String) (attrs : Array (Attr Msg))
    (children : Array (Html Msg)) : String := Id.run do
  unless isValidName tag do
    return out
  let svg := parentSvg || tag == "svg"
  let isTextarea := !svg && tag == "textarea"
  let isSelect := !svg && tag == "select"
  let value? := attrs.foldl (init := none) fun acc attr =>
    match attr with
    | .value "value" v => some (valueText v)
    | _ => acc
  let tagAttrs := if isTextarea || isSelect then
      attrs.filter fun | .value "value" _ => false | _ => true
    else
      attrs
  let mut out := tagAttrs.foldl renderAttr (out ++ s!"<{tag}")
  if !svg && voidElements.contains tag then
    return out ++ ">"
  out := out ++ ">"
  if !svg && newlineDroppingElements.contains tag then
    out := out ++ "\n"
  if let (true, some value) := (isTextarea, value?) then
    return out ++ s!"{escapeText value}</{tag}>"
  let raw := !svg && rawTextElements.contains tag
  let childSvg := svg && tag != "foreignObject"
  let content := children.foldl (fun out h => renderTo out childSvg raw h) ""
  let content := match isSelect, value? with
    | true, some value => String.ofList (markSelected value content.toList)
    | _, _ => content
  return out ++ s!"{content}</{tag}>"

/-- Appends an instance of the template `t` to `out`, with its holes filled and their markers gone. -/
partial def renderTemplate (out : String) (t : Template) (holes : Array (Hole Msg)) : String := Id.run do
  let steps := (t.sites.zip holes).flatMap fun (site, hole) => stepsOf site hole
  let steps := steps.insertionSort fun a b => a.1 < b.1
  let mut out := out
  let mut cursor := 0
  let mut selectMark := 0
  for (pos, step) in steps do
    out := out ++ slice t.html cursor pos
    cursor := pos
    match step with
    | .child h svg =>
      out := renderTo out svg false h
      cursor := pos + "<!>".utf8ByteSize
    | .attr a => out := renderAttr out a
    | .textarea value stop =>
      out := out ++ s!"\n{escapeText value}"
      cursor := stop
    | .selectStart => selectMark := out.utf8ByteSize
    | .selectEnd value =>
      let content := slice out selectMark out.utf8ByteSize
      out := slice out 0 selectMark ++ String.ofList (markSelected value content.toList)
  return out ++ slice t.html cursor t.html.utf8ByteSize

end

end Render

/-- Returns the HTML for `h`, which leaves out handlers and actions. -/
def Html.render (h : Html Msg) : String :=
  Render.renderTo "" false false h

end Lithe
