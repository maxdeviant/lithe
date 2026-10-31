import Lithe.Html
import Lithe.Syntax

open Lithe

/-! Checks what the macro produces, and what it rejects. -/

/-- Returns the HTML of the template that `h` is an instance of. -/
def htmlOf : Html Unit → String
  | .template t _ => t.html
  | _ => "not a template"

/-- Returns the paths of the template that `h` is an instance of. -/
def pathsOf : Html Unit → Array (Array Nat)
  | .template t _ => t.paths
  | _ => #[]

/-- info: "<div class=\"a\" hidden><p>hi</p><br></div>" -/
#guard_msgs in
#eval htmlOf (<div class="a" hidden><p>hi</p><br /></div>)

-- Layout whitespace goes away, but significant whitespace and text that looks like Lean stays.
/-- info: "<p>It's 3 > 2 -- really, <!> <!> left</p>" -/
#guard_msgs in
#eval htmlOf (
  <p>
    It's 3 > 2 -- really, {"a"} {"b"} left
  </p>)

/-- info: "<p> -- not a comment</p>" -/
#guard_msgs in
#eval htmlOf (<p> -- not a comment</p>)

/-- info: "<div><span></span></div>" -/
#guard_msgs in
#eval htmlOf (<div><span /></div>)

-- The extra newline makes up for the one that the HTML parser drops at the start of a `pre`.
/-- info: "<pre>\n\n  a\n  b\n</pre>" -/
#guard_msgs in
#eval htmlOf (<pre>
  a
  b
</pre>)

-- Content holes come first, and paths count the nodes the parser will see.
/-- info: #[#[1, 0], #[0], #[1]] -/
#guard_msgs in
#eval pathsOf (
  <div>
    <input value={"a"} />
    <span class={"b"}>{"c"}</span>
  </div>)

-- Lean keywords work as attribute names, and ordinary comparisons still parse.
/-- info: "<label for=\"a\" class=\"b\" data-for=\"c\" aria-label=\"d\" role=\"e\"></label>" -/
#guard_msgs in
#eval htmlOf (<label for="a" class="b" data-for="c" aria-label="d" role="e" />)

example (a b : Nat) (_ : a < b) : a ≤ b := by omega

/-- info: true -/
#guard_msgs in
#eval (1 < 2 : Bool)

/-- Elements work in holes, under `fun` and `if`, taking their message type from the markup. -/
def nested (xs : Array String) : Html Nat :=
  <ul class={#["a", cls "b" (xs.size < 2)]}>
    {Html.forEach xs id fun x => <li onclick={x.length}>{x}</li>}
    {if xs.isEmpty then <p>none</p> else Html.empty}
  </ul>

def handlers (value : String) : Html String :=
  <div>
    <input {value} oninput={fun (s : String) => s} />
    <input type="checkbox" onchange={fun (b : Bool) => toString b} />
    <form onsubmit={preventDefault "sent"}><button onclick={"clicked"}>Send</button></form>
    <input onkeydown={fun (e : Event) => if e.key == "Enter" then some "enter" else none} />
    <x-widget anything="ok" />
  </div>

/-- error: unknown element `dvi` -/
#guard_msgs in
example : Html Unit := <dvi>hi</dvi>

/-- error: `div` has no attribute `clas` -/
#guard_msgs in
example : Html Unit := <div clas="x">hi</div>

/-- error: `div` has no attribute `href` -/
#guard_msgs in
example : Html Unit := <div href={"x"}>hi</div>

/-- error: unknown event attribute `onclik` -/
#guard_msgs in
example : Html Unit := <div onclik={()}>hi</div>

/-- error: `onclick` needs a value in braces, not a string -/
#guard_msgs in
example : Html Unit := <div onclick="alert()">hi</div>

/-- error: closing tag `span` doesn't match `div` -/
#guard_msgs in
example : Html Unit := <div>hi</span>

/-- error: `br` is a void element, so it must be written `<br />` -/
#guard_msgs in
example : Html Unit := <br>hi</br>

/-- error: `tr` can't be a child of `table`, as the HTML parser would move it -/
#guard_msgs in
example : Html Unit := <table><tr /></table>

/-- error: `div` can't be inside of `p`, as the HTML parser would close it -/
#guard_msgs in
example : Html Unit := <p><span><div /></span></p>

/-- error: `a` can't be inside of `a`, as the HTML parser would close it -/
#guard_msgs in
example : Html Unit := <a><b><a /></b></a>

/-- error: `li` can't be a child of `li`, as the HTML parser would close it -/
#guard_msgs in
example : Html Unit := <li><li /></li>

/-- error: `table` can't contain text, as the HTML parser would move it -/
#guard_msgs in
example : Html Unit := <table>oops</table>

/-- error: `textarea` can't have a child hole, as its content is plain text -/
#guard_msgs in
example : Html Unit := <textarea>{"a"}</textarea>

/-- info: "<optgroup><option></option></optgroup>" -/
#guard_msgs in
#eval htmlOf (<optgroup><option /></optgroup>)

/-- error: `optgroup` can't be a child of `option`, as the HTML parser would close it -/
#guard_msgs in
example : Html Unit := <option><optgroup /></option>

/-- error: `optgroup` can't be a child of `optgroup`, as the HTML parser would move it -/
#guard_msgs in
example : Html Unit := <optgroup><optgroup /></optgroup>

/-- error: `div` has the attribute `class` more than once -/
#guard_msgs in
example : Html Unit := <div class="a" class={"b"} />

-- More than one action is fine.
example : Html Unit := <div use={fun _ => pure (pure ())} use={fun _ => pure (pure ())} />

/-- error: `math` can't be used in markup: MathML isn't supported yet -/
#guard_msgs in
example : Html Unit := <math />

/-- Returns whether the template that `h` is an instance of has to be parsed inside of `svg`. -/
def svgOf : Html Unit → Bool
  | .template t _ => t.svg
  | _ => false

-- SVG names keep their case, and self-closed elements are written out like any other.
/-- info: "<svg viewBox=\"0 0 10 10\"><linearGradient id=\"g\"></linearGradient><path d=\"M0 0\" stroke-width=\"2\"></path></svg>" -/
#guard_msgs in
#eval htmlOf (
  <svg viewBox="0 0 10 10">
    <linearGradient id="g" />
    <path d="M0 0" stroke-width="2" />
  </svg>)

-- Only a root that the HTML parser wouldn't recognize needs `svg` around it when parsing.
/-- info: [false, true, true, false, false] -/
#guard_msgs in
#eval [(<svg />), (<rect />), (<image />), (<a />), (<title>t</title>)].map svgOf

-- `image` isn't void in SVG, and `a` and `title` follow SVG's rules here, not HTML's.
/-- info: "<svg><image></image><a><a></a></a><title><!></title><style><!></style></svg>" -/
#guard_msgs in
#eval htmlOf (<svg><image /><a><a /></a><title>{"t"}</title><style>{"s"}</style></svg>)

/-- info: #[#[1, 0], #[0]] -/
#guard_msgs in
#eval pathsOf (<svg><circle r={1} /><text>{"t"}</text></svg>)

-- HTML in `foreignObject` follows HTML's rules, but only those that apply across SVG.
/-- info: "<p><svg><foreignObject><div><br></div></foreignObject></svg></p>" -/
#guard_msgs in
#eval htmlOf (<p><svg><foreignObject><div><br /></div></foreignObject></svg></p>)

/-- error: `a` can't be inside of `a`, as the HTML parser would close it -/
#guard_msgs in
example : Html Unit := <a><svg><foreignObject><a /></foreignObject></svg></a>

/-- error: `div` isn't an SVG element, so HTML has to go in `foreignObject` -/
#guard_msgs in
example : Html Unit := <svg><div /></svg>

/-- error: `div` isn't an SVG element, so HTML has to go in `foreignObject` -/
#guard_msgs in
example : Html Unit := <rect><div /></rect>

/-- error: `video` isn't an SVG element, so HTML has to go in `foreignObject` -/
#guard_msgs in
example : Html Unit := <svg><video /></svg>

/-- error: `lineargradient` isn't an SVG element, so HTML has to go in `foreignObject` -/
#guard_msgs in
example : Html Unit := <svg><lineargradient /></svg>

/-- error: `my-element` isn't an SVG element, so HTML has to go in `foreignObject` -/
#guard_msgs in
example : Html Unit := <svg><my-element /></svg>

/-- error: `rect` has no attribute `cx` -/
#guard_msgs in
example : Html Unit := <rect cx="1" />

/-- error: `svg` has no attribute `viewbox` -/
#guard_msgs in
example : Html Unit := <svg viewbox={"0 0 1 1"} />

/-- error: unknown event attribute `onclik` -/
#guard_msgs in
example : Html Unit := <circle onclik={()} />

/-- error: `title` in SVG can't have child elements, only text -/
#guard_msgs in
example : Html Unit := <svg><title><circle /></title></svg>

/-- error: unknown element `circle` -/
#guard_msgs in
example : Html Unit := <foreignObject><circle /></foreignObject>

-- These are all accepted.
example : Html Unit :=
  <svg xmlns="http://www.w3.org/2000/svg" role="img" aria-label="a" data-x="1" class="c" style="d">
    <circle cx={1} transform-origin="center" onclick={()} use={fun _ => pure (pure ())} />
  </svg>

/-- info: "<div><p>a</p></div>" -/
#guard_msgs in
#eval htmlOf (<div>{/- note -/}<p>a</p>{/- note -/}</div>)

/-- info: "<div></div>" -/
#guard_msgs in
#eval htmlOf (<div>{/- outer /- inner -/ <p>{"hidden"}</p> -/}</div>)

-- A line comment ends at the line break, so the brace has to be on the next line.
/-- info: "<div></div>" -/
#guard_msgs in
#eval htmlOf (<div>{-- note
}</div>)

/-- info: "<div></div>" -/
#guard_msgs in
#eval htmlOf (<div>{}</div>)

-- Text around a comment is one node, so what comes after it is at the same index as without one.
/-- info: "<p>ab<!></p>" -/
#guard_msgs in
#eval htmlOf (<p>a{/- note -/}b{"c"}</p>)

/-- info: #[#[1]] -/
#guard_msgs in
#eval pathsOf (<p>a{/- note -/}b{"c"}</p>)

/-- info: #[#[1]] -/
#guard_msgs in
#eval pathsOf (<p>{/- note -/}a{/- note -/}{"c"}</p>)

-- Whitespace is handled as if the comment weren't there.
/-- info: "<p>a b</p>" -/
#guard_msgs in
#eval htmlOf (
  <p>
    a
    {/- note -/}
    b
  </p>)

/-- info: #[#[0], #[1]] -/
#guard_msgs in
#eval pathsOf (
  <p>
    {"a"}
    {/- note -/}
    {"b"}
  </p>)

/-- error: HTML comments aren't supported, so write `{/- ... -/}` instead -/
#guard_msgs in
example : Html Unit := <div><!-- note --></div>

/-- error: HTML comments aren't supported, so write `{/- ... -/}` instead -/
#guard_msgs in
example : Html Unit := <div>a <!-- <p>{hidden}</p> --> b</div>

-- Comparisons on several lines aren't mistaken for an element after an expression.
example (a b : Nat) : Bool :=
  a
    < b

/-! `preventDefault` and `stopPropagation` take anything that can respond to events. -/

inductive HandlerMsg where
  | add
  | set (s : String)

def onEvent (e : Event) : HandlerMsg := .set e.key

example : Html HandlerMsg := <form onsubmit={preventDefault HandlerMsg.add}></form>
example : Html HandlerMsg := <form onsubmit={preventDefault .add}></form>
example : Html HandlerMsg := <form onsubmit={preventDefault (.set "a")}></form>
example : Html HandlerMsg := <form onsubmit={preventDefault onEvent}></form>
example : Html HandlerMsg := <form onsubmit={preventDefault HandlerMsg.set}></form>
example : Html HandlerMsg := <form onsubmit={stopPropagation onEvent}></form>
example : Html HandlerMsg := <form onsubmit={stopPropagation .add}></form>
example : Html HandlerMsg := <form onsubmit={preventDefault (stopPropagation onEvent)}></form>

/-- info: (true, true) -/
#guard_msgs in
#eval
  let h : Handler HandlerMsg :=
    ToHandler.toHandler (preventDefault (stopPropagation onEvent))
  (h.preventDefault, h.stopPropagation)

/-! Options in holes. -/

example (x : Option String) : Html Unit := <p>{x}</p>
example (xs : Array String) : Html Unit := <p>{xs[0]?}</p>
example (x : Option String) : Html Unit := <div>{x.map fun s => <p>{s}</p>}</div>

/-! A handler that takes the event's value, in an element nested in a lambda. -/
section
private inductive SetMsg where
  | set (value : String)

example (xs : Array String) : Html SetMsg :=
  <div>{Html.forEach xs id fun x => <input value={x} oninput={SetMsg.set} />}</div>
end

/-! `select` and `textarea` have a `value` property, which only holes can set. -/
example (s : String) : Html Unit := <textarea value={s}></textarea>
example (s : String) : Html Unit := <select value={s}><option value="a">A</option></select>

/-- error: `textarea` has no attribute `value` -/
#guard_msgs in
example : Html Unit := <textarea value="a"></textarea>
example (x : Option String) (f : String → Html Unit) : Html Unit := <div>{x.map f}</div>
example (xs : Array String) : Html Unit :=
  <div>{(xs[0]? : Option String).map fun s => <p>{s}</p>}</div>
