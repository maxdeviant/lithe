import Lithe

open Lithe

/-! Every declaration here has a parse error, for `tests/run.js` to check the message of. -/

def plain : Nat := 1

def afterLet (n : Nat) : Html Unit :=
  let x := n
  <p>{x}</p>

def afterLetWithAttributes (n : Nat) : Html Unit :=
  let x := toString n
  <p title={x} class="a">{x}</p>

def unterminated : Html Unit :=
  <div>
    <!-- note </div>
