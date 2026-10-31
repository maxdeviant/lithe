import Lithe.Render
import Lithe.Syntax

open Lithe

/-! Checks the HTML that views render to. -/

/-- Returns the HTML for `h`. -/
def render (h : Html Unit) : String := h.render

/-- info: "<div class=\"a\" hidden><p>hi</p><br></div>" -/
#guard_msgs in
#eval render (<div class="a" hidden><p>hi</p><br /></div>)

-- Markers are gone, and holes go where they were written, whatever the width of the text around them.
/-- info: "<p title=\"é\" id=\"x\">éaé<b>c</b>b</p>" -/
#guard_msgs in
#eval render (<p title="é" id={"x"}>é{"a"}é<b>{"c"}</b>{"b"}</p>)

-- Static HTML is the author's, and holes are escaped.
/-- info: "<p title=\"&quot;\">&nbsp;&lt;img src=x&gt; &amp;amp;</p>" -/
#guard_msgs in
#eval render (<p title="&quot;">&nbsp;{"<img src=x>"} {"&amp;"}</p>)

/-- info: "<p title=\"&quot;&gt;&lt;script&gt;\"></p>" -/
#guard_msgs in
#eval render (<p title={"\"><script>"} />)

-- Holes with nothing to show leave nothing behind.
/-- info: "<div><input></div>" -/
#guard_msgs in
#eval render (
  <div title={(none : Option String)} hidden={false}>
    {(none : Option String)}
    <input disabled={false} />
  </div>)

-- Hole attributes come after static ones, as they do when mounting.
/-- info: "<input id=\"a\" type=\"checkbox\" checked>" -/
#guard_msgs in
#eval render (<input checked={true} id="a" type="checkbox" />)

-- Handlers and actions have no form in HTML.
/-- info: "<button>a</button>" -/
#guard_msgs in
#eval render (<button onclick={()} use={fun _ => pure (pure ())}>a</button>)

-- This has no attribute, so it's dropped.
/-- info: "<input>" -/
#guard_msgs in
#eval render (.elem "input" #[.value "indeterminate" (.bool true)] #[])

/-- info: "<textarea rows=\"2\">\n&lt;a&gt;\n</textarea>" -/
#guard_msgs in
#eval render (<textarea value={"<a>\n"} rows={2}>ignored</textarea>)

/-- info: "<textarea>\n</textarea>" -/
#guard_msgs in
#eval render (<textarea value={""} />)

/-- info: "<select id=\"s\"><option value=\"a\">A</option><option value=\"b\" selected>B</option></select>" -/
#guard_msgs in
#eval render (
  <select value={"b"} id={"s"}>
    <option value="a">A</option>
    <option value="b">B</option>
  </select>)

-- Options can come from holes, and have their values from their text.
/-- info: "<select><option>a b</option><option selected>&lt;c&gt;</option><option>d</option></select>" -/
#guard_msgs in
#eval render (
  <select value={"<c>"}>
    {Html.forEach #["a b", "<c>", "d"] id fun o => <option>{o}</option>}
  </select>)

-- Only the first match is selected, attributes are told apart from text, and no match is allowed.
/-- info: "<select><optgroup label=\"&lt;option value=&quot;x&quot;&gt;\"><option title=\" value=\" value=\"x\" selected>y</option><option value=\"x\">z</option></optgroup></select>" -/
#guard_msgs in
#eval render (
  <select value={"x"}>
    <optgroup label={"<option value=\"x\">"}>
      <option title=" value=" value="x">y</option>
      <option value="x">z</option>
    </optgroup>
  </select>)

/-- info: "<select><option>a</option></select>" -/
#guard_msgs in
#eval render (<select value={"z"}><option>a</option></select>)

-- SVG fragments don't need anything around them, and don't have void elements.
/-- info: "<svg viewBox=\"0 0 1 1\"><rect width=\"1\"></rect><image></image><text>a</text></svg>" -/
#guard_msgs in
#eval render (
  <svg viewBox="0 0 1 1">
    {(<rect width={1} /> : Html Unit)}
    <image />
    <text>{"a"}</text>
  </svg>)

/-- info: "abc" -/
#guard_msgs in
#eval render (.keyed #[("1", .text "a"), ("2", .keyed #[("3", .text "b")]), ("4", .empty), ("5", .text "c")])

-- Elements built at run time.
/-- info: "<div id=\"&quot;\"><br>a &amp; b</div>" -/
#guard_msgs in
#eval render (.elem "div" #[.value "id" (.str "\""), .on "click" { run := fun _ => none }]
  #[.elem "br" #[] #[], .text "a & b"])

/-- info: "<pre>\n\na</pre>" -/
#guard_msgs in
#eval render (.elem "pre" #[] #[.text "\na"])

/-- info: "<textarea rows=\"1\">\n&lt;</textarea>" -/
#guard_msgs in
#eval render (.elem "textarea" #[.value "value" (.str "<"), .value "rows" (.str "1")] #[.text "ignored"])

/-- info: "<select><option selected>a</option></select>" -/
#guard_msgs in
#eval render (.elem "select" #[.value "value" (.str "a")] #[.elem "option" #[] #[.text "a"]])

-- What's only void or raw text in HTML isn't either in SVG, where the parser decodes everything.
/-- info: "<svg><br></br><style>&lt;img&gt;</style><foreignObject><br><style>a<b</style></foreignObject></svg>" -/
#guard_msgs in
#eval render (.elem "svg" #[] #[
  .elem "br" #[] #[],
  .elem "style" #[] #[.text "<img>"],
  .elem "foreignObject" #[] #[.elem "br" #[] #[], .elem "style" #[] #[.text "a<b"]]])

-- So is a hole in SVG markup, which the macro records.
/-- info: "<svg><style>&lt;img&gt;</style></svg>" -/
#guard_msgs in
#eval render (<svg>{(.elem "style" #[] #[.text "<img>"] : Html Unit)}</svg>)

-- Text that isn't trusted can't get out of a raw text element.
/-- info: "<script>a<b<\\/script><img></script>" -/
#guard_msgs in
#eval render (.elem "script" #[] #[.text "a<b</script><img>"])

-- Names that could add markup are dropped, as the DOM wouldn't accept them either.
/-- info: "<p></p>" -/
#guard_msgs in
#eval render (.elem "p" #[.value "a onload=x" (.str "b"), .value "" (.str "c")]
  #[.elem "x><script>" #[] #[]])
