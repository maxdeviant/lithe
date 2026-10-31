import LitheTest.Util

open Lithe LitheTest

/-! Checks that the HTML from rendering views parses to what mounting them builds. -/

def views : Array (String × Html Unit) := #[
  ("text and entities", <p title="&amp;é" id={"\"<>&"}>&nbsp;é{"<b>&amp;"}é<b>{(1 : Nat)}</b>{"x"}</p>),
  ("carriage returns", <p title={"a\r\nb\rc"}>{"a\r\nb\rc"}</p>),
  ("empty holes", <div hidden={false}>{(none : Option String)}{""}<br />{Html.empty}</div>),
  ("keyed lists", <ul>{Html.forEach #[(1 : Nat), 2] id fun n => <li>{n}</li>}</ul>),
  ("inputs",
    <form>
      <input value={"a\"b"} />
      <input value="static" />
      <input type="checkbox" checked={true} />
      <input type="checkbox" checked={false} />
      <input type="checkbox" checked />
    </form>),
  ("a textarea with a hole", <textarea value={"\nline\n<&>"} rows={2} />),
  ("a textarea with text", <textarea value={"new"}>old</textarea>),
  ("a textarea without a value", <textarea>old</textarea>),
  ("a select with static options",
    <select value={"b"} id={"s"}>
      <option value="a">A</option>
      <option value="b">B</option>
    </select>),
  ("a select with options from text",
    <select value={"<c> d"}>
      <option>a</option>
      {Html.forEach #["<c> d", "e"] id fun o => <option>{o}</option>}
    </select>),
  ("a select in groups",
    <select value={"b"}>
      <optgroup label="<option value=&quot;b&quot;>"><option value="a">A</option></optgroup>
      <optgroup label="2"><option value="b">B</option></optgroup>
    </select>),
  ("a preformatted hole", <pre>{"\nkept"}</pre>),
  ("a table",
    <table><tbody>{Html.forEach #[(1 : Nat)] id fun n => <tr><td>{n}</td></tr>}</tbody></table>),
  ("SVG",
    <svg viewBox="0 0 1 1" class={#["a"]}>
      <linearGradient gradientUnits={"userSpaceOnUse"} />
      {(<rect width={1}><title>{"<t>"}</title></rect> : Html Unit)}
      {Html.forEach #[1] id fun n => <circle r={n} />}
      <image />
      <text>{"<t>"}</text>
      {(.elem "style" #[] #[.text "<x>"] : Html Unit)}
      <foreignObject>
        <div><input value={"v"} /></div>
        {(.elem "br" #[] #[] : Html Unit)}
      </foreignObject>
    </svg>),
  ("elements built at run time",
    .elem "div" #[.value "id" (.str "\""), .value "hidden" (.bool true), .value "title" .absent] #[
      .text "a & <b>",
      .elem "br" #[] #[],
      .elem "pre" #[] #[.text "\nb"],
      .elem "textarea" #[.value "value" (.str "\nc")] #[],
      .elem "select" #[.value "value" (.str "e")] #[
        .elem "option" #[] #[.text "d"],
        .elem "option" #[] #[.text "e"]],
      .elem "style" #[] #[.text "a > b { }"],
      .elem "script" #[.value "type" (.str "text/plain")] #[.text "a<b && c"],
      .elem "svg" #[] #[.elem "circle" #[] #[]]])
]

def main : IO Unit := do
  for (name, view) in views do
    let root ← newRoot
    let rt : Runtime Unit ← Runtime.new root.val fun _ => pure ()
    discard <| rt.mount root.val .null view
    checkEq name (← describeParsed view.render) (← describeDom root.val)
    root.remove
  IO.println "finished"
