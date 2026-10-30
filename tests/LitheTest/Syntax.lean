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

/-- error: `svg` can't be used in markup: SVG isn't supported yet -/
#guard_msgs in
example : Html Unit := <svg />

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
