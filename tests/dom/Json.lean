import LitheTest.JsonCases
import LitheTest.Util

open Lithe LitheTest LitheTest.JsonCases

/-!
Checks `Lithe.Json` against what JS has built in, which is an implementation that it shares nothing
with: `JSON.parse` for what's valid, and `Number` for reading and writing floats.
-/

/-- Returns whether `JSON.parse` accepts `s`. -/
@[extern js inline "(() => { try { JSON.parse(#1.toString()); return 1; } catch { return 0; } })()"]
opaque jsAccepts (s : @& String) : BaseIO Bool

/-- Returns what `JSON.parse` reads `s` as, written by `JSON.stringify`, with keys sorted. -/
@[extern js inline "$rt.mkString(JSON.stringify(((v) => { const sort = (x) => Array.isArray(x) ? x.map(sort) : x && typeof x === 'object' ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, sort(x[k])])) : x; return sort(v); })(JSON.parse(#1.toString()))))"]
opaque jsNormal (s : @& String) : BaseIO String

/-- Returns the float that `Number` reads `s` as. -/
@[extern js inline "Number(#1.toString())"]
opaque jsNumber (s : @& String) : BaseIO Float

/-- Returns the significant digits of what JS writes for `x`. -/
@[extern js inline "$rt.mkString(String(Math.abs(#1)).replace(/e.*$/, '').replace('.', '').replace(/^0+/, '').replace(/0+$/, ''))"]
opaque jsDigits (x : Float) : BaseIO String

/-- Returns the value of `JSON.parse` for `s`. -/
@[extern js inline "JSON.parse(#1.toString())"]
opaque jsParse (s : @& String) : BaseIO JsValue

/-- Returns the significant digits of the number in JSON text. -/
def digitsOf (text : String) : String :=
  let mantissa := ((text.dropWhile (· == '-')).takeWhile (· != 'e')).toString
  let digits := mantissa.replace "." ""
  ((digits.dropWhile (· == '0')).dropEndWhile (· == '0')).toString

structure JsPoint where
  x : Float
  y : Float
  deriving ToJson, FromJs, BEq

inductive JsColor where
  | red | blue
  deriving ToJson, FromJs, BEq

inductive JsShape where
  | circle (center : JsPoint) (radius : Float)
  | empty
  deriving ToJson, FromJs, BEq

inductive JsTree where
  | leaf
  | node (left : JsTree) (value : Nat) (right : JsTree)
  deriving ToJson, FromJs, BEq

structure JsModel where
  count : Nat
  delta : Int
  title : String
  done : Bool
  ratio : Float
  tags : Array String
  items : List Nat
  pair : Nat × String
  maybe : Option Nat
  note? : Option String := none
  color : JsColor
  shape : JsShape
  empty : JsShape
  tree : JsTree
  deriving ToJson, FromJs, BEq

def main : IO Unit := do
  for failure in failures do
    IO.println s!"FAIL {failure}"

  let mut disagreements := 0
  for text in invalid ++ valid.map (·.1) ++ #[nested Json.Parser.maxDepth] do
    if (← jsAccepts text) != (Json.parse text).toOption.isSome then
      disagreements := disagreements + 1
      IO.println s!"FAIL `JSON.parse` disagrees about {repr text}"
  checkEq "what's valid matches `JSON.parse`" disagreements 0

  let mut different := 0
  for (text, _) in valid do
    if let .ok j := Json.parse text then
      -- JS strings can hold a lone surrogate, and Lean strings have U+FFFD in its place.
      if !j.compress.contains '\ufffd' then
        if (← jsNormal j.compress) != (← jsNormal text) then
          different := different + 1
          IO.println s!"FAIL {repr text} became {j}"
  checkEq "values match `JSON.parse`" different 0

  let mut wrongDigits := 0
  let mut wrongValues := 0
  for x in floats do
    let text := Json.encode x
    if x.isFinite then
      if (← jsNumber text).toBits != x.toBits then
        wrongValues := wrongValues + 1
        IO.println s!"FAIL `Number` reads {text} as something else"
      if digitsOf text != (← jsDigits x) then
        wrongDigits := wrongDigits + 1
        IO.println s!"FAIL {text} has other digits than JS writes: {← jsDigits x}"
  checkEq s!"floats read back with `Number`, of {floats.size}" wrongValues 0
  checkEq "floats have the digits that JS writes" wrongDigits 0

  let mut wrongRounding := 0
  for text in decimals do
    let expected ← jsNumber text
    match (Json.decode text : Except String Float) with
    | .ok x =>
      if x.toBits != expected.toBits then
        wrongRounding := wrongRounding + 1
        IO.println s!"FAIL {text} is {x.toBits}, and in JS {expected.toBits}"
    | .error e => IO.println s!"FAIL {text}: {e}"
  checkEq s!"reading decimals rounds like `Number`, of {decimals.size}" wrongRounding 0

  let model : JsModel := {
    count := 2 ^ 40
    delta := -5
    title := "é日本 😀 \"</script>\\\n"
    done := true
    ratio := 0.1 + 0.2
    tags := #["a", "b"]
    items := [1, 2]
    pair := (3, "x")
    maybe := none
    color := .blue
    shape := .circle { x := 1.5, y := -2 } 3
    empty := .empty
    tree := .node (.node .leaf 1 .leaf) 2 .leaf
  }
  let read : JsModel ← fromJs (← jsParse (Json.encode model))
  check "`JSON.parse` and `FromJs` read what `ToJson` writes" (read == model)

  for line in transcript do
    IO.println s!"json {line}"
  IO.println "finished"
