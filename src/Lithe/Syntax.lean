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

/-- Returns whether the input has `chars` at `pos`. -/
def inputHasAt (c : ParserContext) (pos : String.Pos.Raw) : List Char → Bool
  | [] => true
  | ch :: rest => !c.atEnd pos && c.get pos == ch && inputHasAt c (c.next pos) rest

/-- An HTML comment, which is only parsed so that the macro can suggest what to write instead. -/
def markupHtmlComment : Parser := {
  fn := fun c s =>
    let startPos := s.pos
    if !inputHasAt c startPos ['<', '!', '-', '-'] then
      s.mkError "expected an HTML comment"
    else
      let rec find (fuel : Nat) (pos : String.Pos.Raw) : Option String.Pos.Raw :=
        match fuel with
        | 0 => none
        | fuel + 1 =>
          if c.atEnd pos then
            none
          else if inputHasAt c pos ['-', '-', '>'] then
            some (pos + "-->")
          else
            find fuel (c.next pos)
      match find c.inputString.utf8ByteSize (startPos + "<!--") with
      | some endPos => mkNodeToken `Lithe.markupHtmlComment startPos false c (s.setPos endPos)
      -- Past the start, as otherwise the parser would try the next alternative, and report that.
      | none => s.mkUnexpectedErrorAt "unterminated HTML comment" (c.next startPos) }
@[combinator_parenthesizer markupHtmlComment] def markupHtmlComment.parenthesizer : Parenthesizer :=
  pure ()
@[combinator_formatter markupHtmlComment] def markupHtmlComment.formatter : Formatter := pure ()

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

/-- Fails unless there is a line break before what comes next. -/
def afterLinebreak : Parser := checkLinebreakBefore "expected a line break"
@[combinator_parenthesizer afterLinebreak] def afterLinebreak.parenthesizer : Parenthesizer :=
  pure ()
@[combinator_formatter afterLinebreak] def afterLinebreak.formatter : Formatter := pure ()

/-- Fails with an explanation of what happens to an element that follows an expression. -/
def markupAfterExpr : Parser := {
  fn := fun _ s => s.mkUnexpectedError
    "markup here is read as `<` comparing the line above with this tag, so end the line above with `;`" }
@[combinator_parenthesizer markupAfterExpr] def markupAfterExpr.parenthesizer : Parenthesizer :=
  pure ()
@[combinator_formatter markupAfterExpr] def markupAfterExpr.formatter : Formatter := pure ()

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
  (markupText <|> markupHtmlComment <|> markupChild)* "</" markupName markupGt : markupElement
scoped syntax (name := childHole) "{" term markupRBrace : markupChild
-- Lean's comments are whitespace, so a comment among children is a hole with nothing in it.
scoped syntax (name := childComment) "{" markupRBrace : markupChild
scoped syntax (name := childElement) markupElement : markupChild
-- Below `arg` precedence, so that `a < b` is never read as applying `a` to an element.
scoped syntax:lead (name := markup) markupElement markupEnd : term

-- This never succeeds. An element after a `let` is otherwise a comparison, whose error doesn't
-- help, and the parser that gets the furthest wins. Comparisons are unaffected, as the tag is
-- atomic, so this only gets further than one if it finds a whole tag.
scoped syntax:50 term:51 afterLinebreak
  atomic("<" markupName markupAttr* (markupGt <|> markupSelfClose)) markupAfterExpr : term

/-- The attributes that aren't in the standards data but that every element accepts. -/
def ariaAttributes : List String := ["role"]

/-- The attributes that aren't in the SVG standards data but that SVG elements accept. -/
def svgExtraAttributes : List String := ["transform-origin", "xmlns"]

/-- The SVG elements whose content the HTML parser reads as HTML, so that only text belongs there. -/
def svgTextElements : List String := ["desc", "script", "style", "title"]

/-- The elements that the HTML parser closes when nesting another, even from inside of SVG. -/
def unscopedExclusions : List String := ["a", "form"]

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

/-- The elements that only make sense in a place that templates can't reach, or need a namespace. -/
def unsupportedElements : List (String × String) :=
  [("html", "it is outside of what an app renders"),
    ("head", "it is outside of what an app renders"),
    ("body", "it is outside of what an app renders"),
    ("frameset", "it is outside of what an app renders"),
    ("template", "its content is inert, so holes can't reach it"),
    ("math", "MathML isn't supported yet")]

/-- Returns the text of a name. -/
def nameText (n : Syntax) : String := n[0].getAtomVal

/-- Returns whether `tag` is the name of a custom element, which may have any attributes. -/
def isCustomElement (tag : String) : Bool :=
  tag.contains '-'

/--
Returns whether the root element `tag` can only be SVG. The HTML parser would turn `image` into `img`,
and so it counts as SVG. Tags that are also HTML, such as `a`, are HTML here, as nothing says otherwise.
-/
def isSvgFragment (tag : String) : Bool :=
  HtmlData.svgTagNames.contains tag && (tag == "image" || !HtmlData.tagNames.contains tag)

/-- A hole for an attribute. -/
structure AttrHole where
  /-- The value of the hole. -/
  term : Term
  /-- The path to the element. -/
  path : Array Nat
  /-- The element's tag. -/
  tag : String
  /-- The attribute's name. -/
  name : String
  /-- The position of the `>` of the element's opening tag. -/
  tagEnd : Nat := 0
  /-- The position of the end of the element's content. -/
  contentEnd : Nat := 0

/-- The state of compiling markup. -/
structure State where
  /-- The HTML so far. -/
  html : String := ""
  /-- The holes for content, with their paths and sites. -/
  childHoles : Array (Term × Array Nat × Term) := #[]
  /-- The holes for attributes. -/
  attrHoles : Array AttrHole := #[]

abbrev CompileM := StateT State MacroM

/-- Appends `s` to the HTML. -/
def emit (s : String) : CompileM Unit :=
  modify fun st => { st with html := st.html ++ s }

/-- Checks that the attribute `name` is valid on the element `tag`, which is SVG if `svg`. -/
def checkAttr (tag : String) (svg : Bool) (ref : Syntax) (name : String) : CompileM Unit := do
  if !svg && isCustomElement tag then
    return
  if name.startsWith "data-" || name.startsWith "aria-" then
    return
  if name.startsWith "on" then
    unless HtmlData.eventAttributes.contains name do
      Macro.throwErrorAt ref s!"unknown event attribute `{name}`"
    return
  let isKnown :=
    if svg then
      HtmlData.svgGlobalAttributes.contains name || svgExtraAttributes.contains name
        || ((HtmlData.svgElementAttributes.lookup tag).getD []).contains name
    else
      HtmlData.globalAttributes.contains name
        || ((HtmlData.elementAttributes.lookup tag).getD []).contains name
  unless isKnown || ariaAttributes.contains name do
    Macro.throwErrorAt ref s!"`{tag}` has no attribute `{name}`"

/-- Adds the hole for the attribute `name` with the value `value`. -/
def attrHole (tag : String) (svg : Bool) (ref : Syntax) (path : Array Nat) (name : String)
    (value : Term) : CompileM Unit := do
  -- Type class failures are reported at the code that the macro generates, not at `value`.
  let hole ← withRef value do
    let attr ← if name == "use" then
        `(Lithe.Attr.use $value)
      else if name.startsWith "on" && name.length > 2 then
        checkAttr tag svg ref name
        let event := Syntax.mkStrLit (name.drop 2).toString
        `(Lithe.Attr.on $event (Lithe.ToHandler.toHandler $value))
      else
        -- These have a `value` property but no such attribute, and holes set live properties.
        unless name == "value" && (tag == "select" || tag == "textarea") do
          checkAttr tag svg ref name
        `(Lithe.Attr.value $(Syntax.mkStrLit name) (Lithe.ToAttrValue.toAttrValue $value))
    `(Lithe.Hole.attr $attr)
  modify fun st => { st with attrHoles := st.attrHoles.push { term := hole, path, tag, name } }

/-- Compiles an attribute of the element `tag` at `path`. -/
def compileAttr (tag : String) (svg : Bool) (path : Array Nat) (attr : Syntax) : CompileM Unit := do
  if attr.isOfKind ``attrStr then
    let name := nameText attr[0]
    if name == "use" || name.startsWith "on" then
      Macro.throwErrorAt attr[0] s!"`{name}` needs a value in braces, not a string"
    checkAttr tag svg attr[0] name
    let some value := attr[2].isStrLit? | Macro.throwUnsupported
    emit s!" {name}=\"{value.replace "\"" "&quot;"}\""
  else if attr.isOfKind ``attrTerm then
    attrHole tag svg attr[0] path (nameText attr[0]) ⟨attr[3]⟩
  else if attr.isOfKind ``attrBare then
    let name := nameText attr[0]
    checkAttr tag svg attr[0] name
    emit s!" {name}"
  else if attr.isOfKind ``attrShort then
    attrHole tag svg attr[1] path attr[1].getId.toString ⟨attr[1]⟩
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
  -- An `optgroup` is where an `option` belongs, even though the reverse closes the `option`.
  let isOptionInGroup := tag == "option" && parent == "optgroup"
  if !isOptionInGroup && siblingGroups.any fun g => g.contains tag && g.contains parent then
    Macro.throwErrorAt ref s!"`{tag}` can't be a child of `{parent}`, as the HTML parser would close it"
  if rawTextElements.contains parent then
    Macro.throwErrorAt ref s!"`{parent}` can't have child elements, as its content is plain text"

/-- Returns the name that the attribute `attr` sets. -/
def attrName (attr : Syntax) : String :=
  if attr.isOfKind ``attrShort then attr[1].getId.toString else nameText attr[0]

/-- Throws an error if `attrs` sets something twice, which the DOM and the HTML parser resolve oppositely. -/
def checkDuplicateAttrs (tag : String) (attrs : Array Syntax) : CompileM Unit := do
  let mut seen : List String := []
  for attr in attrs do
    let name := attrName attr
    if name != "use" then
      if seen.contains name then
        Macro.throwErrorAt attr s!"`{tag}` has the attribute `{name}` more than once"
      seen := name :: seen

/-- Records where the attribute holes from `first` to `last` are in the HTML. -/
def setAttrExtent (first last tagEnd contentEnd : Nat) : CompileM Unit :=
  modify fun st => { st with
    attrHoles := st.attrHoles.mapIdx fun i h =>
      if first ≤ i && i < last then { h with tagEnd, contentEnd } else h }

/-- Returns the current length of the HTML, in bytes. -/
def htmlSize : CompileM Nat := do
  return (← get).html.utf8ByteSize

/--
Checks that `tag` is an SVG element. This also covers what the HTML parser would restructure, as the
elements that make it leave SVG, such as `div`, aren't SVG elements.
-/
def checkSvgElement (ref : Syntax) (tag : String) : CompileM Unit := do
  unless HtmlData.svgTagNames.contains tag do
    Macro.throwErrorAt ref s!"`{tag}` isn't an SVG element, so HTML has to go in `foreignObject`"

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

/--
Removes comments from `children`, and joins the text around them, as it is one node to the HTML
parser. Throws an error for an HTML comment.
-/
def removeComments (children : Array Syntax) : CompileM (Array Syntax) :=
  children.foldlM (init := #[]) fun acc child => do
    if child.isOfKind `Lithe.markupHtmlComment then
      Macro.throwErrorAt child "HTML comments aren't supported, so write `{/- ... -/}` instead"
    if child.isOfKind ``childComment then
      return acc
    match acc.back? with
    | some prev =>
      if prev.isOfKind `Lithe.markupText && child.isOfKind `Lithe.markupText then
        let text := prev[0].getAtomVal ++ child[0].getAtomVal
        return acc.pop.push (mkNode `Lithe.markupText #[mkAtomFrom prev text])
      return acc.push child
    | none => return acc.push child

mutual

/--
Compiles the element `el` at `path`, whose parent is the head of `ancestors` unless `inSvg`, which
says that its parent is SVG. In that case, `ancestors` has only the HTML elements around the SVG.
-/
partial def compileElement (el : Syntax) (path : Array Nat) (ancestors : List String)
    (inSvg : Bool) : CompileM Unit := do
  let tag := nameText el[1]
  if inSvg then
    checkSvgElement el[1] tag
  else
    checkNesting el[1] tag ancestors
  let svg := inSvg || tag == "svg"
  checkDuplicateAttrs tag el[2].getArgs
  emit s!"<{tag}"
  let firstAttr := (← get).attrHoles.size
  for attr in el[2].getArgs do
    compileAttr tag svg path attr
  let lastAttr := (← get).attrHoles.size
  let tagEnd ← htmlSize
  let isVoid := !svg && HtmlData.voidElements.contains tag
  if el.isOfKind ``elementSelfClosed then
    -- The HTML parser ignores `/>`, so an element that isn't void would swallow what follows it.
    setAttrExtent firstAttr lastAttr tagEnd (tagEnd + ">".utf8ByteSize)
    emit (if isVoid then ">" else s!"></{tag}>")
    return
  if nameText el[6] != tag then
    Macro.throwErrorAt el[6] s!"closing tag `{nameText el[6]}` doesn't match `{tag}`"
  if isVoid then
    Macro.throwErrorAt el[1] s!"`{tag}` is a void element, so it must be written `<{tag} />`"
  emit ">"
  if newlineDroppingElements.contains tag then
    emit "\n"
  -- What's in `foreignObject` is HTML again, in which most of the parser's rules stop at this element.
  let (childAncestors, childSvg) :=
    if tag == "foreignObject" && svg then
      (ancestors.filter unscopedExclusions.contains, false)
    else if svg then
      (ancestors, true)
    else
      (tag :: ancestors, false)
  let mut index := 0
  for child in ← removeComments el[4].getArgs do
    if ← compileChild child (path.push index) tag childAncestors childSvg then
      index := index + 1
  setAttrExtent firstAttr lastAttr tagEnd (← htmlSize)
  emit s!"</{tag}>"

/--
Compiles a child at `path` of the element `parent`, which is SVG if `inSvg`, returning whether it
added a DOM node.
-/
partial def compileChild (child : Syntax) (path : Array Nat) (parent : String)
    (ancestors : List String) (inSvg : Bool) : CompileM Bool := do
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
    -- The HTML parser only treats these as plain text outside of SVG.
    if !inSvg && rawTextElements.contains parent then
      Macro.throwErrorAt child
        s!"`{parent}` can't have a child hole, as its content is plain text"
    let value : Term := ⟨child[1]⟩
    -- Type class failures are reported at the code that the macro generates, not at `value`.
    let hole ← withRef value `(Lithe.Hole.child (Lithe.ToChild.toChild $value))
    let site ← `(Lithe.Template.Site.child $(Syntax.mkNumLit (toString (← htmlSize))) $(quote inSvg))
    modify fun st => { st with childHoles := st.childHoles.push (hole, path, site) }
    emit "<!>"
    return true
  else if child.isOfKind ``childElement then
    if inSvg && svgTextElements.contains parent then
      Macro.throwErrorAt child s!"`{parent}` in SVG can't have child elements, only text"
    compileElement child[0] path ancestors inSvg
    return true
  else
    Macro.throwUnsupported

end

/-- Expands markup to a `Lithe.Html.template`. -/
@[macro markup] def expandMarkup : Macro := fun stx => do
  let svg := isSvgFragment (nameText stx[0][1])
  let ((), st) ← (compileElement stx[0] #[] [] svg).run {}
  -- Content comes first, so that `value` on a `select` is set after its options exist.
  let holes := st.childHoles.map (fun (term, path, _) => (term, path))
    ++ st.attrHoles.map fun h => (h.term, h.path)
  let terms := holes.map (·.1)
  let paths ← holes.mapM fun (_, path) => do
    let indices := path.map (Syntax.mkNumLit <| toString ·)
    `(#[$indices,*])
  let attrSites ← st.attrHoles.mapM fun h => do
    let num (n : Nat) := Syntax.mkNumLit (toString n)
    if h.name == "value" && h.tag == "textarea" then
      `(Lithe.Template.Site.textarea $(num (h.tagEnd + 1)) $(num h.contentEnd))
    else if h.name == "value" && h.tag == "select" then
      `(Lithe.Template.Site.select $(num h.tagEnd) $(num h.contentEnd))
    else
      `(Lithe.Template.Site.attr $(num h.tagEnd))
  let sites := st.childHoles.map (·.2.2) ++ attrSites
  let key := s!"{st.html}\x00{holes.map (·.2)}"
  `(Lithe.Html.template
      (Lithe.Template.mk $(Syntax.mkStrLit st.html) #[$paths,*] $(Syntax.mkStrLit key) $(quote svg)
        #[$sites,*])
      #[$terms,*])

end Lithe
