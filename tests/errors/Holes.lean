import Lithe

open Lithe

/-! Every hole here has an error, for `tests/run.js` to check the position of. -/

inductive Msg where
  | go

def attr (badAttr : Nat → Nat) : Html Msg :=
  <main>
    <input
      value={badAttr}
    />
  </main>

def child (badChild : Nat → Nat) : Html Msg :=
  <main>
    <p>{badChild}</p>
  </main>

def handler : Html Msg :=
  <main>
    <button onclick={42}>Go</button>
  </main>

def action : Html Msg :=
  <main>
    <input use={42} />
  </main>

def unknownField (n : Nat) : Html Msg :=
  <main>
    <input value={n.nope} />
  </main>
