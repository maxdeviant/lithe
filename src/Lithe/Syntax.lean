module

public meta import Lean
public import Lithe.Html
public meta import Lithe.Syntax.HtmlData

/-!
Markup syntax, which is available after `open Lithe`.

The macro splits markup into the static HTML of a `Template` and its dynamic holes. It checks the
markup as it goes, including for anything that the HTML parser would restructure, as that would make
the paths to the holes wrong.

Everything here is `meta`, so it runs only at compile time, and programs don't include it.
-/

public meta section

open Lean Parser PrettyPrinter

namespace Lithe

/-- A tag or attribute name, which may be a Lean keyword, or contain `-`. -/
def markupName : Parser :=
  withAntiquot (mkAntiquot "markupName" `Lithe.markupName) {
    fn := fun c s =>
      let startPos := s.pos
      let s := takeWhile1Fn (fun ch => ch.isAlphanum || ch == '-') "expected a name" c s
      mkNodeToken `Lithe.markupName startPos true c s }
@[combinator_parenthesizer markupName] def markupName.parenthesizer : Parenthesizer := pure ()
@[combinator_formatter markupName] def markupName.formatter : Formatter := pure ()

/-- Literal text, which keeps its whitespace and has no comments. -/
def markupText : Parser :=
  withAntiquot (mkAntiquot "markupText" `Lithe.markupText) {
    fn := fun c s =>
      let startPos := s.pos
      let s := takeWhile1Fn (fun ch => ch != '<' && ch != '{' && ch != '}') "expected text" c s
      mkNodeToken `Lithe.markupText startPos true c s }
@[combinator_parenthesizer markupText] def markupText.parenthesizer : Parenthesizer := pure ()
@[combinator_formatter markupText] def markupText.formatter : Formatter := pure ()

/--
Returns the parser function for a token that leaves what follows it alone, as what follows a tag may
be significant whitespace, or text that looks like a Lean comment.
-/
def rawTokenFn (kind : SyntaxNodeKind) (chars : List Char) : ParserFn := fun c s =>
  let startPos := s.pos
  let s := chars.foldl (fun s ch => satisfyFn (· == ch) s!"expected '{ch}'" c s) s
  mkNodeToken kind startPos false c s

/-- The `>` that ends a tag. -/
def markupGt : Parser := { fn := rawTokenFn `Lithe.markupGt ['>'] }
@[combinator_parenthesizer markupGt] def markupGt.parenthesizer : Parenthesizer := pure ()
@[combinator_formatter markupGt] def markupGt.formatter : Formatter := pure ()

/-- The `/>` that ends a self-closing tag. -/
def markupSelfClose : Parser := { fn := rawTokenFn `Lithe.markupSelfClose ['/', '>'] }
@[combinator_parenthesizer markupSelfClose] def markupSelfClose.parenthesizer : Parenthesizer :=
  pure ()
@[combinator_formatter markupSelfClose] def markupSelfClose.formatter : Formatter := pure ()

/-- The `}` that ends a hole among an element's children. -/
def markupRBrace : Parser := { fn := rawTokenFn `Lithe.markupRBrace ['}'] }
@[combinator_parenthesizer markupRBrace] def markupRBrace.parenthesizer : Parenthesizer := pure ()
@[combinator_formatter markupRBrace] def markupRBrace.formatter : Formatter := pure ()

/-- The whitespace after the outermost tag, which is back in ordinary Lean. -/
def markupEnd : Parser := { fn := whitespace }
@[combinator_parenthesizer markupEnd] def markupEnd.parenthesizer : Parenthesizer := pure ()
@[combinator_formatter markupEnd] def markupEnd.formatter : Formatter := pure ()

declare_syntax_cat markupAttr
declare_syntax_cat markupElement
declare_syntax_cat markupChild

scoped syntax (name := attrStr) markupName "=" str : markupAttr
scoped syntax (name := attrTerm) markupName "=" "{" term "}" : markupAttr
scoped syntax (name := attrBare) markupName : markupAttr
scoped syntax (name := attrShort) "{" ident "}" : markupAttr
scoped syntax (name := elementSelfClosed) "<" markupName markupAttr* markupSelfClose : markupElement
-- Text is parsed outside of the category, as a category parser can't start at whitespace.
scoped syntax (name := elementOpen) "<" markupName markupAttr* markupGt
  (markupText <|> markupChild)* "</" markupName markupGt : markupElement
scoped syntax (name := childHole) "{" term markupRBrace : markupChild
scoped syntax (name := childElement) markupElement : markupChild
-- Below `arg` precedence, so that `a < b` is never read as applying `a` to an element.
scoped syntax:lead (name := markup) markupElement markupEnd : term

/-- The attributes that aren't in the standards data but that every element accepts. -/
def ariaAttributes : List String := ["role"]

/-- The elements whose content the HTML parser doesn't treat as markup. -/
def rawTextElements : List String := ["script", "style", "textarea", "title"]

/-- The elements in which the HTML parser drops a newline at the start of the content. -/
def newlineDroppingElements : List String := ["pre", "textarea", "listing"]

/-- The elements in which whitespace is significant. -/
def preformattedElements : List String := ["pre", "textarea", "listing", "script", "style"]

/-- The elements in which the HTML parser moves any text elsewhere. -/
def noTextElements : List String :=
  ["table", "thead", "tbody", "tfoot", "tr", "colgroup", "select", "optgroup"]

/-- The elements that end an open `p` element. -/
def paragraphClosers : List String :=
  ["address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl",
    "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
    "header", "hgroup", "hr", "li", "listing", "main", "menu", "nav", "ol", "p", "plaintext", "pre",
    "search", "section", "summary", "table", "ul", "xmp"]

/-- The elements that the HTML parser won't nest at any depth inside of themselves. -/
def selfExcludingElements : List String := ["a", "button", "form", "nobr"]

/-- The groups of elements that the HTML parser won't nest directly inside of each other. -/
def siblingGroups : List (List String) :=
  [["li"], ["dd", "dt"], ["option", "optgroup"], ["h1", "h2", "h3", "h4", "h5", "h6"]]

/-- The children that the HTML parser allows each element to have without restructuring it. -/
def allowedChildren : List (String × List String) :=
  [("table", ["caption", "colgroup", "thead", "tbody", "tfoot", "script", "style"]),
    ("thead", ["tr", "script", "style"]),
    ("tbody", ["tr", "script", "style"]),
    ("tfoot", ["tr", "script", "style"]),
    ("tr", ["td", "th", "script", "style"]),
    ("colgroup", ["col"]),
    ("select", ["option", "optgroup", "hr"]),
    ("optgroup", ["option"])]

/-- The elements that only make sense in a place that templates can't reach, or need namespaces. -/
def unsupportedElements : List (String × String) :=
  [("html", "it is outside of what an app renders"),
    ("head", "it is outside of what an app renders"),
    ("body", "it is outside of what an app renders"),
    ("frameset", "it is outside of what an app renders"),
    ("template", "its content is inert, so holes can't reach it"),
    ("svg", "SVG isn't supported yet"),
    ("math", "MathML isn't supported yet")]

/-- Returns the text of a name. -/
def nameText (n : Syntax) : String := n[0].getAtomVal

/-- Returns whether `tag` is the name of a custom element, which may have any attributes. -/
def isCustomElement (tag : String) : Bool :=
  tag.contains '-'

/-- The state of compiling markup. -/
structure State where
  /-- The HTML so far. -/
  html : String := ""
  /-- The holes for content, with their paths. -/
  childHoles : Array (Term × Array Nat) := #[]
  /-- The holes for attributes, with their paths. -/
  attrHoles : Array (Term × Array Nat) := #[]

abbrev CompileM := StateT State MacroM

/-- Appends `s` to the HTML. -/
def emit (s : String) : CompileM Unit :=
  modify fun st => { st with html := st.html ++ s }

/-- Checks that the attribute `name` is valid on the element `tag`. -/
def checkAttr (tag : String) (ref : Syntax) (name : String) : CompileM Unit := do
  if isCustomElement tag then
    return
  if name.startsWith "data-" || name.startsWith "aria-" then
    return
  if name.startsWith "on" then
    unless HtmlData.eventAttributes.contains name do
      Macro.throwErrorAt ref s!"unknown event attribute `{name}`"
    return
  let specific := (HtmlData.elementAttributes.lookup tag).getD []
  unless HtmlData.globalAttributes.contains name || ariaAttributes.contains name
      || specific.contains name do
    Macro.throwErrorAt ref s!"`{tag}` has no attribute `{name}`"

/-- Adds the hole for the attribute `name` with the value `value`. -/
def attrHole (tag : String) (ref : Syntax) (path : Array Nat) (name : String) (value : Term) :
    CompileM Unit := do
  -- Type class failures are reported at the code that the macro generates, not at `value`.
  let hole ← withRef value do
    let attr ← if name == "use" then
        `(Lithe.Attr.use $value)
      else if name.startsWith "on" && name.length > 2 then
        checkAttr tag ref name
        let event := Syntax.mkStrLit (name.drop 2).toString
        `(Lithe.Attr.on $event (Lithe.ToHandler.toHandler $value))
      else
        checkAttr tag ref name
        `(Lithe.Attr.value $(Syntax.mkStrLit name) (Lithe.ToAttrValue.toAttrValue $value))
    `(Lithe.Hole.attr $attr)
  modify fun st => { st with attrHoles := st.attrHoles.push (hole, path) }

/-- Compiles an attribute of the element `tag` at `path`. -/
def compileAttr (tag : String) (path : Array Nat) (attr : Syntax) : CompileM Unit := do
  if attr.isOfKind ``attrStr then
    let name := nameText attr[0]
    if name == "use" || name.startsWith "on" then
      Macro.throwErrorAt attr[0] s!"`{name}` needs a value in braces, not a string"
    checkAttr tag attr[0] name
    let some value := attr[2].isStrLit? | Macro.throwUnsupported
    emit s!" {name}=\"{value.replace "\"" "&quot;"}\""
  else if attr.isOfKind ``attrTerm then
    attrHole tag attr[0] path (nameText attr[0]) ⟨attr[3]⟩
  else if attr.isOfKind ``attrBare then
    let name := nameText attr[0]
    checkAttr tag attr[0] name
    emit s!" {name}"
  else if attr.isOfKind ``attrShort then
    attrHole tag attr[1] path attr[1].getId.toString ⟨attr[1]⟩
  else
    Macro.throwUnsupported

/-- Checks that the HTML parser wouldn't restructure `tag` as a child of `ancestors`. -/
def checkNesting (ref : Syntax) (tag : String) (ancestors : List String) : CompileM Unit := do
  if let some reason := unsupportedElements.lookup tag then
    Macro.throwErrorAt ref s!"`{tag}` can't be used in markup: {reason}"
  unless HtmlData.tagNames.contains tag || isCustomElement tag do
    Macro.throwErrorAt ref s!"unknown element `{tag}`"
  if selfExcludingElements.contains tag && ancestors.contains tag then
    Macro.throwErrorAt ref s!"`{tag}` can't be inside of `{tag}`, as the HTML parser would close it"
  if paragraphClosers.contains tag && ancestors.contains "p" then
    Macro.throwErrorAt ref s!"`{tag}` can't be inside of `p`, as the HTML parser would close it"
  let some parent := ancestors.head? | return
  if let some allowed := allowedChildren.lookup parent then
    unless allowed.contains tag do
      Macro.throwErrorAt ref
        s!"`{tag}` can't be a child of `{parent}`, as the HTML parser would move it"
  if siblingGroups.any fun g => g.contains tag && g.contains parent then
    Macro.throwErrorAt ref s!"`{tag}` can't be a child of `{parent}`, as the HTML parser would close it"
  if rawTextElements.contains parent then
    Macro.throwErrorAt ref s!"`{parent}` can't have child elements, as its content is plain text"

/--
Removes whitespace that only lays out the markup: any at either end that contains a newline, as in
Svelte and JSX. Any other run of whitespace containing a newline collapses to a space.
-/
def normalizeText (text : String) : String := Id.run do
  let lines := text.splitOn "\n"
  if lines.length == 1 then
    return text
  let trimmed := lines.zipIdx.map fun (line, i) =>
    let line := if i == 0 then line else line.trimAsciiStart.copy
    if i == lines.length - 1 then line else line.trimAsciiEnd.copy
  return " ".intercalate (trimmed.filter (!·.isEmpty))

mutual

/-- Compiles the element `el` at `path`, whose parent is the head of `ancestors`. -/
partial def compileElement (el : Syntax) (path : Array Nat) (ancestors : List String) :
    CompileM Unit := do
  let tag := nameText el[1]
  checkNesting el[1] tag ancestors
  emit s!"<{tag}"
  for attr in el[2].getArgs do
    compileAttr tag path attr
  let isVoid := HtmlData.voidElements.contains tag
  if el.isOfKind ``elementSelfClosed then
    -- The HTML parser ignores `/>`, so an element that isn't void would swallow what follows it.
    emit (if isVoid then ">" else s!"></{tag}>")
    return
  if nameText el[6] != tag then
    Macro.throwErrorAt el[6] s!"closing tag `{nameText el[6]}` doesn't match `{tag}`"
  if isVoid then
    Macro.throwErrorAt el[1] s!"`{tag}` is a void element, so it must be written `<{tag} />`"
  emit ">"
  if newlineDroppingElements.contains tag then
    emit "\n"
  let mut index := 0
  for child in el[4].getArgs do
    if ← compileChild child (path.push index) tag (tag :: ancestors) then
      index := index + 1
  emit s!"</{tag}>"

/-- Compiles a child at `path` of the element `parent`, returning whether it added a DOM node. -/
partial def compileChild (child : Syntax) (path : Array Nat) (parent : String)
    (ancestors : List String) : CompileM Bool := do
  if child.isOfKind `Lithe.markupText then
    let raw := child[0].getAtomVal
    let text := if preformattedElements.contains parent then raw else normalizeText raw
    if text.isEmpty then
      return false
    if noTextElements.contains parent && !text.trimAscii.isEmpty then
      Macro.throwErrorAt child s!"`{parent}` can't contain text, as the HTML parser would move it"
    emit text
    return true
  else if child.isOfKind ``childHole then
    if rawTextElements.contains parent then
      Macro.throwErrorAt child
        s!"`{parent}` can't have a child hole, as its content is plain text"
    let value : Term := ⟨child[1]⟩
    -- Type class failures are reported at the code that the macro generates, not at `value`.
    let hole ← withRef value `(Lithe.Hole.child (Lithe.ToChild.toChild $value))
    modify fun st => { st with childHoles := st.childHoles.push (hole, path) }
    emit "<!>"
    return true
  else if child.isOfKind ``childElement then
    compileElement child[0] path ancestors
    return true
  else
    Macro.throwUnsupported

end

/-- Expands markup to a `Lithe.Html.template`. -/
@[macro markup] def expandMarkup : Macro := fun stx => do
  let ((), st) ← (compileElement stx[0] #[] []).run {}
  -- Content comes first, so that `value` on a `select` is set after its options exist.
  let holes := st.childHoles ++ st.attrHoles
  let terms := holes.map (·.1)
  let paths ← holes.mapM fun (_, path) => do
    let indices := path.map (Syntax.mkNumLit <| toString ·)
    `(#[$indices,*])
  let key := s!"{st.html}\x00{holes.map (·.2)}"
  `(Lithe.Html.template
      (Lithe.Template.mk $(Syntax.mkStrLit st.html) #[$paths,*] $(Syntax.mkStrLit key))
      #[$terms,*])

end Lithe
