module

/-!
JSON, for sending values between programs, such as from a native server to a client.

It works the same under native Lean and LeanScript, and has no imports from the `Lean` package, as
those link the whole compiler into a native program, however little of them it uses.
-/

public section

namespace Lithe

/--
A JSON number, whose value is `digits × 10 ^ exponent` with the sign given by `negative`. Keeping the
exponent apart means that parsing `1e1000000` doesn't compute that number.
-/
structure Json.Number where
  negative : Bool := false
  digits : Nat
  exponent : Int := 0
  deriving BEq, Inhabited, Repr

/-- A JSON value. Objects keep their fields in order. -/
inductive Json where
  | null
  | bool (b : Bool)
  | num (n : Json.Number)
  | str (s : String)
  | arr (elems : Array Json)
  | obj (fields : Array (String × Json))
  deriving Inhabited

namespace Json

namespace Number

/-- The largest exponent that `toNat?` and `toInt?` expand, so that input can't exhaust memory. -/
def maxExpandedExponent : Nat := 4096

/-- Returns the number with this value in its normal form, which has no trailing zeros in `digits`. -/
partial def normalized (negative : Bool) (digits : Nat) (exponent : Int) : Number :=
  if digits == 0 then
    { negative, digits := 0, exponent := 0 }
  else if digits % 10 == 0 then
    normalized negative (digits / 10) (exponent + 1)
  else
    { negative, digits, exponent }

def ofNat (n : Nat) : Number :=
  normalized false n 0

def ofInt (n : Int) : Number :=
  normalized (n < 0) n.natAbs 0

/-- Returns the value as a `Nat`, if it's a natural number that isn't unreasonably large. -/
def toNat? (n : Number) : Option Nat :=
  if n.digits == 0 then
    some 0
  else if n.negative || n.exponent < 0 || n.exponent > maxExpandedExponent then
    none
  else
    some (n.digits * 10 ^ n.exponent.toNat)

/-- Returns the value as an `Int`, if it's an integer that isn't unreasonably large. -/
def toInt? (n : Number) : Option Int :=
  (toNat? { n with negative := false }).map fun m => if n.negative then -(m : Int) else m

/-- Returns the JSON text of `n`. -/
protected def toString (n : Number) : String :=
  let sign := if n.negative then "-" else ""
  let digits := toString n.digits
  let count := digits.length
  if n.exponent >= 0 then
    if n.exponent <= 21 then
      s!"{sign}{n.digits * 10 ^ n.exponent.toNat}"
    else
      s!"{sign}{digits}e{n.exponent}"
  else
    let places := n.exponent.natAbs
    if places < count then
      let whole := (digits.take (count - places)).toString
      let part := (digits.drop (count - places)).toString
      s!"{sign}{whole}.{part}"
    else if places <= count + 6 then
      let zeros := String.ofList (List.replicate (places - count) '0')
      s!"{sign}0.{zeros}{digits}"
    else
      s!"{sign}{digits}e{n.exponent}"

instance : ToString Number := ⟨Number.toString⟩

/-- Returns the bits of a float from its sign, its exponent field, and its fraction field. -/
private def floatBits (negative : Bool) (exponent fraction : Nat) : UInt64 :=
  UInt64.ofNat ((if negative then 2 ^ 63 else 0) + exponent * 2 ^ 52 + fraction)

/-- Returns the bits of the float closest to `num / den`, rounding ties to even. Neither is zero. -/
private def roundToBits (negative : Bool) (num den : Nat) : UInt64 :=
  -- Scales the quotient to at least 55 bits, which leaves bits to round with.
  let scale : Int := 55 - ((Nat.log2 num : Int) - Nat.log2 den)
  let (q, r) :=
    if scale >= 0 then
      let n := num * 2 ^ scale.toNat
      (n / den, n % den)
    else
      let d := den * 2 ^ scale.natAbs
      (num / d, num % d)
  -- The bit of `q` that becomes the float's lowest has this place value, which subnormals fix.
  let low : Int := max (-1074) ((Nat.log2 q : Int) - scale - 52)
  let shift := (low + scale).toNat
  let kept := q / 2 ^ shift
  let rest := q % 2 ^ shift
  let half := 2 ^ (shift - 1)
  let roundUp := rest > half || (rest == half && (r != 0 || kept % 2 == 1))
  let kept := if roundUp then kept + 1 else kept
  let (kept, low) := if kept >= 2 ^ 53 then (kept / 2, low + 1) else (kept, low)
  if kept < 2 ^ 52 then
    floatBits negative 0 kept
  else if low > 971 then
    floatBits negative 2047 0
  else
    floatBits negative (low + 1075).toNat (kept - 2 ^ 52)

/-- Returns the float closest to `n`, which is infinite if `n` is too large for any other. -/
def toFloat (n : Number) : Float :=
  Float.ofBits <|
    if n.digits == 0 then
      floatBits n.negative 0 0
    else
      -- These only need to be roughly right, as they rule out what's far outside of the range.
      let magnitude := n.exponent + (Nat.log2 n.digits : Int) * 3 / 10
      if magnitude > 320 then
        floatBits n.negative 2047 0
      else if magnitude < -340 then
        floatBits n.negative 0 0
      else if n.exponent >= 0 then
        roundToBits n.negative (n.digits * 10 ^ n.exponent.toNat) 1
      else
        roundToBits n.negative n.digits (10 ^ n.exponent.natAbs)

/-- Returns the largest `t` for which `10 ^ t ≤ num / den`, given a guess that's close to it. -/
private partial def floorLog10 (num den : Nat) (guess : Int) : Int :=
  let atLeast (t : Int) : Bool :=
    if t >= 0 then num >= den * 10 ^ t.toNat else num * 10 ^ t.natAbs >= den
  if !atLeast guess then
    floorLog10 num den (guess - 1)
  else if atLeast (guess + 1) then
    floorLog10 num den (guess + 1)
  else
    guess

/--
Returns the number with the fewest digits that `toFloat` turns back into `x`, which is the closest to
`x` of those with that many, or `none` if `x` is infinite or not a number.
-/
def ofFloat? (x : Float) : Option Number :=
  let bits := x.toBits
  let negative := bits >>> 63 == 1
  let field := ((bits >>> 52) &&& 0x7ff).toNat
  let fraction := (bits &&& 0xfffffffffffff).toNat
  if field == 2047 then
    none
  else if field == 0 && fraction == 0 then
    some (normalized negative 0 0)
  else
    let mantissa := if field == 0 then fraction else fraction + 2 ^ 52
    let binary : Int := (max field 1 : Nat) - (1075 : Int)
    let (above, below) :=
      if binary >= 0 then (mantissa * 2 ^ binary.toNat, 1) else (mantissa, 2 ^ binary.natAbs)
    let guess := ((Nat.log2 above : Int) - Nat.log2 below) * 30103 / 100000
    let top := floorLog10 above below guess
    let rounded (precision : Nat) : Number :=
      let place := top - precision + 1
      let (n, d) :=
        if place >= 0 then (above, below * 10 ^ place.toNat) else (above * 10 ^ place.natAbs, below)
      let q := n / d
      let r := n % d
      let up := 2 * r > d || (2 * r == d && q % 2 == 1)
      normalized negative (if up then q + 1 else q) place
    -- Every float survives 17 digits, and any more digits than enough are also enough.
    let rec search (fuel low high : Nat) : Number :=
      match fuel with
      | 0 => rounded high
      | fuel + 1 =>
        if low >= high then
          rounded high
        else
          let middle := (low + high) / 2
          if (rounded middle).toFloat.toBits == bits then
            search fuel low middle
          else
            search fuel (middle + 1) high
    some (search 8 1 17)

end Number

instance : Coe Nat Json := ⟨(.num <| .ofNat ·)⟩
instance : Coe Int Json := ⟨(.num <| .ofInt ·)⟩
instance : Coe String Json := ⟨.str⟩
instance : Coe Bool Json := ⟨.bool⟩

/-- Returns the value of the field `key` of `j`, where the last of any repeated fields counts. -/
def get? (j : Json) (key : String) : Option Json :=
  match j with
  | .obj fields => (fields.findRev? (·.1 == key)).map (·.2)
  | _ => none

/-- Returns whether `a` and `b` have the same value, regardless of the order of fields. -/
protected partial def beq : Json → Json → Bool
  | .null, .null => true
  | .bool a, .bool b => a == b
  | .num a, .num b => a == b
  | .str a, .str b => a == b
  | .arr a, .arr b => a.size == b.size && (a.zip b).all fun (x, y) => Json.beq x y
  | a@(.obj xs), b@(.obj ys) =>
    xs.size == ys.size && xs.all fun (key, _) =>
      match a.get? key, b.get? key with
      | some x, some y => Json.beq x y
      | _, _ => false
  | _, _ => false

instance : BEq Json := ⟨Json.beq⟩

/-- Returns the hexadecimal digit for `n`, which is below 16. -/
private def hexDigit (n : Nat) : Char :=
  Nat.digitChar n

/-- Appends `c` to `acc`, escaping it if JSON or a surrounding `script` element requires that. -/
private def pushEscaped (acc : String) (c : Char) : String :=
  match c with
  | '"' => acc ++ "\\\""
  | '\\' => acc ++ "\\\\"
  | '\n' => acc ++ "\\n"
  | '\r' => acc ++ "\\r"
  | '\t' => acc ++ "\\t"
  | '<' => acc ++ "\\u003c"
  | c =>
    if c.toNat < 0x20 then
      (acc ++ "\\u00").push (hexDigit (c.toNat / 16)) |>.push (hexDigit (c.toNat % 16))
    else
      acc.push c

/-- Appends `s` to `acc` as a JSON string. -/
private def pushString (acc s : String) : String :=
  (s.foldl pushEscaped (acc.push '"')).push '"'

/-- Appends the JSON text of `j` to `acc`. -/
private partial def pushJson (acc : String) : Json → String
  | .null => acc ++ "null"
  | .bool true => acc ++ "true"
  | .bool false => acc ++ "false"
  | .num n => acc ++ n.toString
  | .str s => pushString acc s
  | .arr elems =>
    let (acc, _) := elems.foldl (init := (acc.push '[', true)) fun (acc, first) elem =>
      (pushJson (if first then acc else acc.push ',') elem, false)
    acc.push ']'
  | .obj fields =>
    let (acc, _) := fields.foldl (init := (acc.push '{', true)) fun (acc, first) (key, value) =>
      (pushJson ((pushString (if first then acc else acc.push ',') key).push ':') value, false)
    acc.push '}'

/--
Returns the JSON text of `j`, without any whitespace. It has `<` escaped wherever it occurs, which
makes it safe to put in a `script` element.
-/
def compress (j : Json) : String :=
  pushJson "" j

instance : ToString Json := ⟨compress⟩

namespace Parser

/--
The deepest nesting that `parse` accepts, so that input can't exhaust the stack. Chrome has the least
stack to work with, and reached a depth of 462 from the top of the stack.
-/
def maxDepth : Nat := 128

/-- A parser of the text it reads from, which keeps its byte offset as the state. -/
abbrev Parser := ReaderT String (EStateM String Nat)

/-- Returns the byte at the offset, or 0 at the end, which is never valid where bytes are compared. -/
@[inline] def peek : Parser UInt8 := do
  let s ← read
  let i ← get
  return if h : i < s.utf8ByteSize then s.getUTF8Byte ⟨i⟩ h else 0

@[inline] def skip (n : Nat := 1) : Parser Unit :=
  modify (· + n)

def fail (message : String) : Parser α := do
  throw s!"{message} at byte {← get}"

partial def ws : Parser Unit := do
  let c ← peek
  if c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09 then
    skip
    ws

/-- Skips `word`, whose bytes are all ASCII. -/
def keyword (word : String) : Parser Unit := do
  let s ← read
  let i ← get
  if String.Pos.Raw.extract s ⟨i⟩ ⟨i + word.utf8ByteSize⟩ == word then
    skip word.utf8ByteSize
  else
    fail "unexpected input"

def isDigit (c : UInt8) : Bool :=
  0x30 ≤ c && c ≤ 0x39

/-- Reads digits into `acc`, and returns it with how many there were. -/
partial def digits (acc count : Nat := 0) : Parser (Nat × Nat) := do
  let c ← peek
  if isDigit c then
    skip
    digits (10 * acc + (c - 0x30).toNat) (count + 1)
  else
    return (acc, count)

def number : Parser Number := do
  let negative := (← peek) == 0x2d
  if negative then
    skip
  let first ← peek
  unless isDigit first do
    fail "expected a digit"
  let whole ← if first == 0x30 then do skip; pure 0 else (·.1) <$> digits
  let (mantissa, places) ← if (← peek) == 0x2e then do
      skip
      let (m, n) ← digits whole
      if n == 0 then
        fail "expected a digit"
      pure (m, n)
    else
      pure (whole, 0)
  let e ← peek
  let exponent : Int ← if e == 0x65 || e == 0x45 then do
      skip
      let sign ← peek
      if sign == 0x2b || sign == 0x2d then
        skip
      let (n, count) ← digits
      if count == 0 then
        fail "expected a digit"
      pure (if sign == 0x2d then -(n : Int) else n)
    else
      pure 0
  return Number.normalized negative mantissa (exponent - places)

/-- Returns the value of a hexadecimal digit. -/
def hexValue (c : UInt8) : Parser Nat :=
  if 0x30 ≤ c && c ≤ 0x39 then
    pure (c - 0x30).toNat
  else if 0x61 ≤ c && c ≤ 0x66 then
    pure (c - 0x61 + 10).toNat
  else if 0x41 ≤ c && c ≤ 0x46 then
    pure (c - 0x41 + 10).toNat
  else
    fail "expected a hexadecimal digit"

/-- Reads the four digits of a `\u` escape. -/
def hex4 : Parser Nat := do
  let mut n := 0
  for _ in [0:4] do
    n := 16 * n + (← hexValue (← peek))
    skip
  return n

/-- Reads an escape, after its backslash. A surrogate without its other half becomes U+FFFD. -/
def escape : Parser Char := do
  let c ← peek
  skip
  match c with
  | 0x22 => return '"'
  | 0x5c => return '\\'
  | 0x2f => return '/'
  | 0x62 => return '\x08'
  | 0x66 => return '\x0c'
  | 0x6e => return '\n'
  | 0x72 => return '\r'
  | 0x74 => return '\t'
  | 0x75 =>
    let high ← hex4
    if high < 0xd800 || high > 0xdfff then
      return Char.ofNat high
    if high > 0xdbff then
      return '�'
    let start ← get
    if (← peek) == 0x5c then
      skip
      if (← peek) == 0x75 then
        skip
        let low ← hex4
        if 0xdc00 ≤ low && low ≤ 0xdfff then
          return Char.ofNat (0x10000 + (high - 0xd800) * 0x400 + (low - 0xdc00))
    set start
    return '�'
  | _ => fail "invalid escape"

/-- Reads the rest of a string, whose text since the last escape began at `start`. -/
partial def stringRest (acc : String) (start : Nat) : Parser String := do
  let c ← peek
  if c == 0x22 then
    let stop ← get
    skip
    return acc ++ String.Pos.Raw.extract (← read) ⟨start⟩ ⟨stop⟩
  else if c == 0x5c then
    let acc := acc ++ String.Pos.Raw.extract (← read) ⟨start⟩ ⟨← get⟩
    skip
    let acc := acc.push (← escape)
    stringRest acc (← get)
  else if c < 0x20 then
    fail "expected the end of a string"
  else
    skip
    stringRest acc start

/-- Reads a string, after its opening quote. -/
def string : Parser String := do
  stringRest "" (← get)

mutual

/-- Reads the rest of an array, which isn't empty. -/
partial def arrayRest (depth : Nat) (acc : Array Json) : Parser (Array Json) := do
  ws
  let acc := acc.push (← value depth)
  ws
  let c ← peek
  if c == 0x2c then
    skip
    arrayRest depth acc
  else if c == 0x5d then
    skip
    return acc
  else
    fail "expected `,` or `]`"

/-- Reads the rest of an object, which isn't empty. -/
partial def objectRest (depth : Nat) (acc : Array (String × Json)) :
    Parser (Array (String × Json)) := do
  ws
  unless (← peek) == 0x22 do
    fail "expected a string"
  skip
  let key ← string
  ws
  unless (← peek) == 0x3a do
    fail "expected `:`"
  skip
  ws
  let acc := acc.push (key, ← value depth)
  ws
  let c ← peek
  if c == 0x2c then
    skip
    objectRest depth acc
  else if c == 0x7d then
    skip
    return acc
  else
    fail "expected `,` or `}`"

/-- Reads a value, inside of `depth` arrays and objects. -/
partial def value (depth : Nat) : Parser Json := do
  let c ← peek
  if c == 0x7b || c == 0x5b then
    if depth >= maxDepth then
      fail "too deeply nested"
    skip
    ws
    if c == 0x7b then
      if (← peek) == 0x7d then
        skip
        return .obj #[]
      return .obj (← objectRest (depth + 1) #[])
    else
      if (← peek) == 0x5d then
        skip
        return .arr #[]
      return .arr (← arrayRest (depth + 1) #[])
  else if c == 0x22 then
    skip
    return .str (← string)
  else if c == 0x74 then
    keyword "true"
    return .bool true
  else if c == 0x66 then
    keyword "false"
    return .bool false
  else if c == 0x6e then
    keyword "null"
    return .null
  else if c == 0x2d || isDigit c then
    return .num (← number)
  else
    fail "unexpected input"

end

/-- Reads a value that is all of the input, other than whitespace around it. -/
def document : Parser Json := do
  ws
  let j ← value 0
  ws
  if (← get) < (← read).utf8ByteSize then
    fail "expected the end of the input"
  return j

end Parser

/-- Parses JSON text, or returns a description of what's wrong with it. -/
def parse (s : String) : Except String Json :=
  match Parser.document s 0 with
  | .ok j _ => .ok j
  | .error message _ => .error message

end Json

/-- Types that can be written as JSON. Use `deriving ToJson` to get an instance. -/
class ToJson (α : Type) where
  toJson : α → Json

/-- Types that can be read from JSON. Use `deriving FromJson` to get an instance. -/
class FromJson (α : Type) where
  fromJson? : Json → Except String α

export ToJson (toJson)
export FromJson (fromJson?)

namespace Json

/-- Returns the value that `s` is the JSON text of. -/
def decode [FromJson α] (s : String) : Except String α :=
  parse s >>= fromJson?

/-- Returns the JSON text of `a`. -/
def encode [ToJson α] (a : α) : String :=
  (toJson a).compress

/-- Returns an error that says `j` isn't what was expected. -/
def mismatch (expected : String) (j : Json) : Except String α :=
  .error s!"expected {expected}, got {j}"

/-- Returns an error unless `j` is an object. -/
def expectObject (j : Json) : Except String Unit :=
  match j with
  | .obj _ => pure ()
  | _ => mismatch "an object" j

/-- Reads the field `key` of the object `j`, where a missing field counts as `null`. -/
def getField [FromJson α] (j : Json) (key : String) : Except String α :=
  match fromJson? ((j.get? key).getD .null) with
  | .ok a => .ok a
  | .error e => .error s!"{key}: {e}"

/-- Returns an error for a constructor named `kind`, which isn't any of `kinds`. -/
def unknownKind (kinds : Array String) (kind : String) : Except String α :=
  .error s!"expected one of {", ".intercalate kinds.toList}, got {kind}"

end Json

instance : ToJson Json := ⟨id⟩
instance : FromJson Json := ⟨.ok⟩

instance : ToJson Json.Number := ⟨.num⟩
instance : FromJson Json.Number where
  fromJson?
    | .num n => .ok n
    | j => Json.mismatch "a number" j

instance : ToJson Bool := ⟨.bool⟩
instance : FromJson Bool where
  fromJson?
    | .bool b => .ok b
    | j => Json.mismatch "a boolean" j

instance : ToJson String := ⟨.str⟩
instance : FromJson String where
  fromJson?
    | .str s => .ok s
    | j => Json.mismatch "a string" j

instance : ToJson Nat := ⟨(.num <| .ofNat ·)⟩
instance : FromJson Nat where
  fromJson?
    | j@(.num n) => match n.toNat? with
      | some m => .ok m
      | none => Json.mismatch "a natural number" j
    | j => Json.mismatch "a natural number" j

instance : ToJson Int := ⟨(.num <| .ofInt ·)⟩
instance : FromJson Int where
  fromJson?
    | j@(.num n) => match n.toInt? with
      | some m => .ok m
      | none => Json.mismatch "an integer" j
    | j => Json.mismatch "an integer" j

/-- Returns an error if `n` isn't below `size`, and otherwise converts it with `f`. -/
def Json.bounded (size : Nat) (f : Nat → α) (j : Json) : Except String α := do
  let n : Nat ← fromJson? j
  if n < size then
    return f n
  Json.mismatch s!"a natural number below {size}" j

instance : ToJson UInt8 := ⟨(toJson ·.toNat)⟩
instance : FromJson UInt8 := ⟨Json.bounded UInt8.size UInt8.ofNat⟩
instance : ToJson UInt16 := ⟨(toJson ·.toNat)⟩
instance : FromJson UInt16 := ⟨Json.bounded UInt16.size UInt16.ofNat⟩
instance : ToJson UInt32 := ⟨(toJson ·.toNat)⟩
instance : FromJson UInt32 := ⟨Json.bounded UInt32.size UInt32.ofNat⟩
instance : ToJson UInt64 := ⟨(toJson ·.toNat)⟩
instance : FromJson UInt64 := ⟨Json.bounded UInt64.size UInt64.ofNat⟩

/-- Writes a number with as few digits as read back exactly, or a string for what JSON can't write. -/
instance : ToJson Float where
  toJson x :=
    match Json.Number.ofFloat? x with
    | some n => .num n
    | none => .str (if x.isNaN then "NaN" else if x > 0 then "Infinity" else "-Infinity")

instance : FromJson Float where
  fromJson?
    | .num n => .ok n.toFloat
    | .str "NaN" => .ok (0.0 / 0.0)
    | .str "Infinity" => .ok (1.0 / 0.0)
    | .str "-Infinity" => .ok (-1.0 / 0.0)
    | j => Json.mismatch "a number" j

instance : ToJson Unit := ⟨fun _ => .null⟩
instance : FromJson Unit := ⟨fun _ => .ok ()⟩

instance [ToJson α] : ToJson (Option α) where
  toJson
    | some a => toJson a
    | none => .null

/-- Reads `null` as `none`. -/
instance [FromJson α] : FromJson (Option α) where
  fromJson?
    | .null => .ok none
    | j => some <$> fromJson? j

instance [ToJson α] : ToJson (Array α) := ⟨(.arr <| ·.map toJson)⟩
instance [FromJson α] : FromJson (Array α) where
  fromJson?
    | .arr elems => elems.mapM fromJson?
    | j => Json.mismatch "an array" j

instance [ToJson α] : ToJson (List α) := ⟨(toJson ·.toArray)⟩
instance [FromJson α] : FromJson (List α) where
  fromJson? j := Array.toList <$> (fromJson? j : Except String (Array α))

instance [ToJson α] [ToJson β] : ToJson (α × β) := ⟨fun (a, b) => .arr #[toJson a, toJson b]⟩
instance [FromJson α] [FromJson β] : FromJson (α × β) where
  fromJson?
    | .arr #[a, b] => return (← fromJson? a, ← fromJson? b)
    | j => Json.mismatch "an array of two items" j

end Lithe
