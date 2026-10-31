module

public import Lithe.Core

open Lithe

/-! Checks of `Lithe.Json` that have to give the same results under native Lean and LeanScript. -/

namespace LitheTest.JsonCases

public section

structure Point where
  x : Float
  y : Float
  deriving ToJson, FromJson, BEq

structure Labeled (α : Type) where
  label : String
  value : α
  note? : Option String := none
  deriving ToJson, FromJson, BEq

structure Point3 extends Point where
  z : Float
  deriving ToJson, FromJson, BEq

inductive Color where
  | red | green | blue
  deriving ToJson, FromJson, BEq

inductive Shape where
  | circle (center : Point) (radius : Float)
  | rect (corner : Point) (width height : Float)
  | empty
  deriving ToJson, FromJson, BEq

inductive Tree (α : Type) where
  | leaf
  | node (left : Tree α) (value : α) (right : Tree α)
  deriving ToJson, FromJson, BEq

structure Everything where
  nat : Nat
  int : Int
  text : String
  flag : Bool
  byte : UInt8
  big : UInt64
  ratio : Float
  list : List Nat
  pair : Nat × String
  maybe : Option Nat
  color : Color
  shape : Shape
  tree : Tree Nat
  labeled : Labeled Color
  point : Point3
  deriving ToJson, FromJson, BEq

/-- Returns the JSON of each kind of value, each of which has to be read back as the same value. -/
def encoded : Array String × Array String := Id.run do
  let mut texts := #[]
  let mut failures := #[]
  let roundTrip {α} [ToJson α] [FromJson α] [BEq α] (a : α) : String × Option String :=
    let text := Json.encode a
    let failure := match (Json.decode text : Except String α) with
      | .ok b => if a == b then none else some s!"{text} was read back as {Json.encode b}"
      | .error e => some s!"{text} couldn't be read back: {e}"
    (text, failure)
  let shape := Shape.rect { x := 0.5, y := -1 } 2 3
  let tree : Tree Nat := .node (.node .leaf 1 .leaf) 2 .leaf
  let everything : Everything := {
    nat := 2 ^ 70
    int := -(10 ^ 25)
    text := "é日本 😀 \"<\\\n\t\x01"
    flag := true
    byte := 255
    big := 18446744073709551615
    ratio := 0.1 + 0.2
    list := [1, 2]
    pair := (3, "x")
    maybe := none
    color := .green
    shape
    tree
    labeled := { label := "l", value := .blue, note? := some "n" }
    point := { x := 1, y := 2, z := 1e300 }
  }
  for (text, failure) in [
      roundTrip everything,
      roundTrip Color.red,
      roundTrip Shape.empty,
      roundTrip (Shape.circle { x := 1, y := 2 } 3),
      roundTrip shape,
      roundTrip tree,
      roundTrip ({ label := "a", value := 1 } : Labeled Nat),
      roundTrip ([] : List Nat),
      roundTrip (some (1 : Nat), (none : Option Nat))] do
    texts := texts.push text
    if let some f := failure then
      failures := failures.push f
  return (texts, failures)

/-- Exact text for values whose form is decided. -/
def writes : Array (String × String) := #[
  (Json.encode (Labeled.mk "a" (1 : Nat) none), "{\"label\":\"a\",\"value\":1,\"note\":null}"),
  (Json.encode Color.red, "\"red\""),
  (Json.encode Shape.empty, "{\"kind\":\"empty\"}"),
  (Json.encode (Shape.circle { x := 1, y := 2 } 3),
    "{\"kind\":\"circle\",\"center\":{\"x\":1,\"y\":2},\"radius\":3}"),
  (Json.encode ((1 : Nat), "x"), "[1,\"x\"]"),
  (Json.encode (100 : Nat), "100"),
  (Json.encode ((10 : Nat) ^ 30), "1e30"),
  (Json.encode (-(5 : Int)), "-5"),
  (Json.encode (1.5 : Float), "1.5"),
  (Json.encode (100.0 : Float), "100"),
  (Json.encode (0.001 : Float), "0.001"),
  (Json.encode (0.1 + 0.2 : Float), "0.30000000000000004"),
  (Json.encode (1e21 : Float), "1000000000000000000000"),
  (Json.encode (1e300 : Float), "1e300"),
  (Json.encode (-0.0 : Float), "-0"),
  (Json.encode (1.0 / 0.0 : Float), "\"Infinity\""),
  (Json.encode (-1.0 / 0.0 : Float), "\"-Infinity\""),
  (Json.encode (0.0 / 0.0 : Float), "\"NaN\""),
  (Json.encode "</script><!--", "\"\\u003c/script>\\u003c!--\""),
  (Json.encode "\x00\x1f\x7f\"\\/", "\"\\u0000\\u001f\x7f\\\"\\\\/\""),
  ((Json.obj #[("b", (1 : Nat)), ("a", .arr #[.null, .bool false])]).compress,
    "{\"b\":1,\"a\":[null,false]}")
]

/-- Text that isn't JSON. -/
def invalid : Array String := #[
  "", " ", "01", "-01", "1.", ".5", "+1", "1e", "1e+", "-", "--1", "0x10", "1_000", "NaN", "Infinity",
  "tru", "True", "nul", "[", "]", "{", "}", "[1,]", "[,1]", "[1 2]", "{\"a\":1,}", "{,}", "{a:1}",
  "{\"a\"}", "{\"a\":}", "{1:1}", "'a'", "\"", "\"a", "\"\n\"", "\"\t\"", "\"\\x\"", "\"\\u12\"",
  "\"\\u12g4\"", "\"\\", "1 2", "null x", "[]]", "//", "/**/1", "\x00"
]

/-- Text that is JSON, with its value written in the form that `compress` gives it. -/
def valid : Array (String × String) := #[
  ("null", "null"),
  (" \t\r\n[ 1 , { \"a\" : true } ] \n", "[1,{\"a\":true}]"),
  ("0", "0"),
  ("-0", "-0"),
  ("0.0", "0"),
  ("1.50", "1.5"),
  ("1E2", "100"),
  ("1e+2", "100"),
  ("1000e-3", "1"),
  ("0e5", "0"),
  ("123456789012345678901234567890", "123456789012345678901234567890"),
  ("1e1000000", "1e1000000"),
  ("1e-1000000", "1e-1000000"),
  ("\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"", "\"\\\"\\\\/\\u0008\\u000c\\n\\r\\t\""),
  ("\"\\u00e9\\u65E5\"", "\"é日\""),
  ("\"\\ud83d\\ude00\"", "\"😀\""),
  ("\"😀é\"", "\"😀é\""),
  ("\"\\ud83d\"", "\"\ufffd\""),
  ("\"\\ude00\"", "\"\ufffd\""),
  ("\"\\ud83dx\"", "\"\ufffdx\""),
  ("\"\\ud83d\\n\"", "\"\ufffd\\n\""),
  ("\"\\ud83d\\u0041\"", "\"\ufffdA\""),
  ("{\"a\":1,\"a\":2}", "{\"a\":1,\"a\":2}"),
  ("[]", "[]"),
  ("{}", "{}"),
  ("[[],{}]", "[[],{}]")
]

/-- Returns text nested `depth` arrays deep. -/
def nested (depth : Nat) : String :=
  String.ofList (List.replicate depth '[' ++ List.replicate depth ']')

/-- Returns the pseudorandom numbers after `seed`, which are the same on every target. -/
def randoms (seed : UInt64) (count : Nat) : Array UInt64 := Id.run do
  let mut x := seed
  let mut result := Array.emptyWithCapacity count
  for _ in [0:count] do
    x := x * 6364136223846793005 + 1442695040888963407
    result := result.push (x ^^^ (x >>> 29))
  return result

/-- The bit patterns of floats to try, which cover every magnitude and also round numbers. -/
def floatBits : Array UInt64 :=
  randoms 1 400 ++ (randoms 2 200).map (fun x => (x &&& 0x800fffffffffffff) ||| 0x3ff0000000000000)
    ++ (randoms 3 100).map (· &&& 0x800fffffffffffff) ++ #[
      0, 1, 2, 0xfffffffffffff, 0x10000000000000, 0x7fefffffffffffff, 0x3ff0000000000000,
      0x3ff0000000000001, 0x8000000000000000, 0x4340000000000000, 0x4340000000000001,
      0x3cb0000000000000, 0x7ff0000000000000, 0xfff0000000000000]

/-- The floats to try, without those that aren't numbers, whose bits differ between targets. -/
def floats : Array Float :=
  (floatBits.map Float.ofBits).filter (!·.isNaN)

/-- Decimal text to try reading, including numbers exactly halfway between two floats. -/
def decimals : Array String :=
  #["1e23", "8.41e21", "2.2250738585072011e-308", "2.2250738585072014e-308", "5e-324", "2.4703282292062328e-324",
    "2.4703282292062327e-324", "1.7976931348623157e308", "1.7976931348623158e308",
    "1.797693134862315807e308", "1.797693134862315808e308", "9007199254740993", "9007199254740992.5",
    "9007199254740995", "0.1", "0.30000000000000004", "1e400", "-1e400", "1e-400", "-1e-400",
    "123456789012345678901234567890123456789012345678901234567890"]
    ++ (randoms 4 300).map fun (x : UInt64) =>
      let exponent : Int := ((x >>> 20) % 640).toNat
      s!"{x.toNat}e{exponent - 340}"

/-- Returns a description of each check that failed. -/
def failures : Array String := Id.run do
  let mut out := encoded.2
  for (actual, expected) in writes do
    if actual != expected then
      out := out.push s!"wrote {actual}, expected {expected}"
  for text in invalid do
    if let .ok j := Json.parse text then
      out := out.push s!"read {repr text} as {j}"
  for (text, expected) in valid do
    match Json.parse text with
    | .ok j =>
      if j.compress != expected then
        out := out.push s!"read {repr text} as {j}, expected {expected}"
    | .error e => out := out.push s!"couldn't read {repr text}: {e}"
  match Json.parse (nested Json.Parser.maxDepth) with
  | .ok j =>
    if j.compress != nested Json.Parser.maxDepth then
      out := out.push "nested arrays changed"
  | .error e => out := out.push s!"couldn't read the deepest nesting allowed: {e}"
  if (Json.parse (nested (Json.Parser.maxDepth + 1))).toOption.isSome then
    out := out.push "read more than the deepest nesting allowed"
  -- A value as deep as what can be read has to get through the deriving handlers too.
  let deep : Tree Nat := (List.range 42).foldl (fun t n => .node t n .leaf) .leaf
  match (Json.decode (Json.encode deep) : Except String (Tree Nat)) with
  | .ok t =>
    if !(t == deep) then
      out := out.push "a deep tree changed"
  | .error e => out := out.push s!"couldn't read a deep tree: {e}"
  for x in floats do
    let text := Json.encode x
    match (Json.decode text : Except String Float) with
    | .ok y =>
      if x.toBits != y.toBits then
        out := out.push s!"{text} was read back with the bits {y.toBits}, not {x.toBits}"
    | .error e => out := out.push s!"{text} couldn't be read back: {e}"
  let numberOf (text : String) : Option Json.Number :=
    match Json.parse text with
    | .ok (.num n) => some n
    | _ => none
  if ((numberOf "1e1000000").bind (·.toNat?)).isSome then
    out := out.push "expanded 1e1000000"
  if (((numberOf "1e4096").bind (·.toNat?)) != some (10 ^ 4096)) then
    out := out.push "didn't expand 1e4096"
  if ((numberOf "1.5").bind (·.toNat?)).isSome || ((numberOf "-1").bind (·.toNat?)).isSome then
    out := out.push "read something else as a natural number"
  for (name, result) in [
      ("a byte out of range", (Json.decode "256" : Except String UInt8).toOption.isSome),
      ("a UInt64 out of range", (Json.decode "18446744073709551616" : Except String UInt64).toOption.isSome),
      ("a string as a number", (Json.decode "\"1\"" : Except String Nat).toOption.isSome),
      ("a number as a structure", (Json.decode "1" : Except String Point).toOption.isSome),
      ("a missing field", (Json.decode "{\"x\":1}" : Except String Point).toOption.isSome),
      ("an unknown enum case", (Json.decode "\"mauve\"" : Except String Color).toOption.isSome),
      ("an unknown kind", (Json.decode "{\"kind\":\"blob\"}" : Except String Shape).toOption.isSome),
      ("a pair of three", (Json.decode "[1,2,3]" : Except String (Nat × Nat)).toOption.isSome)] do
    if result then
      out := out.push s!"read {name}"
  if !(Json.decode "{\"label\":\"a\",\"value\":1}" : Except String (Labeled Nat)).toOption.isSome then
    out := out.push "didn't read a missing optional field"
  if ((Json.parse "{\"a\":1,\"a\":2}").toOption.bind (·.get? "a")) != some (2 : Nat) then
    out := out.push "the first of a repeated field counted"
  match (Json.decode "{\"x\":\"no\",\"y\":1}" : Except String Point) with
  | .error e =>
    if e != "x: expected a number, got \"no\"" then
      out := out.push s!"the error was {e}"
  | .ok _ => out := out.push "read a string as a float"
  return out

/-- What has to come out the same on every target. -/
def transcript : Array String :=
  encoded.1 ++ floats.map Json.encode ++ decimals.map fun text =>
    match Json.decode text with
    | .ok (x : Float) => toString x.toBits
    | .error e => e

end

end LitheTest.JsonCases
