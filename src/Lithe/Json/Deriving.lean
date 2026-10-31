module

public import Lithe.Json
public meta import Lean.Elab.Deriving.Basic
public meta import Lean.Elab.Deriving.Util

/-!
Deriving handlers for `ToJson` and `FromJson`, which use the same form as `Js.Deriving`, so that what
a native program writes can also be read with `JSON.parse` and `FromJs`.

A structure is an object with a field for each of its fields, named without any trailing `?`. An
inductive type whose constructors have no fields is the name of a constructor, as a string. Any other
inductive type is an object with a `kind` field, which is the name of the constructor, and a field
for each of its fields. Every one of those must have a name other than `kind`.
-/

namespace Lithe.Json.Deriving

open Lean Elab Command Term Meta Deriving

/-- The field that holds the name of an inductive type's constructor. -/
meta def kindKey : String := "kind"

/-- Returns the name of the JSON field for the field `field`. -/
meta def fieldKey (field : Name) : String :=
  field.getString!.dropEndWhile (· == '?') |>.copy

/-- A constructor of an inductive type, as the deriving handlers see it. -/
meta structure Ctor where
  val : ConstructorVal
  /-- The name of the constructor, which identifies it in JSON. -/
  kind : String
  /-- The names of the constructor's fields, which are `none` for fields without names. -/
  fields : Array (Option Name)

/-- Returns the constructors of the inductive type `indVal`. -/
meta def getCtors (indVal : InductiveVal) : MetaM (Array Ctor) :=
  indVal.ctors.toArray.mapM fun name => do
    let val ← getConstInfoCtor name
    forallTelescopeReducing val.type fun xs _ => do
      let fields ← xs[indVal.numParams...*].toArray.mapM fun x => do
        let n := (← x.fvarId!.getDecl).userName
        return if n.hasMacroScopes then none else some n
      return { val, kind := name.getString!, fields }

/-- Returns the JSON fields for the fields of `ctor`, or an error if they can't all have one. -/
meta def Ctor.fieldKeys (ctor : Ctor) (className : Name) : MetaM (Array String) :=
  ctor.fields.mapM fun
    | none => throwError "cannot derive `{className}` for constructor `{ctor.val.name}`, since \
        some of its fields have no names"
    | some n => do
      let key := fieldKey n.eraseMacroScopes
      if key == kindKey then
        throwError "cannot derive `{className}` for constructor `{ctor.val.name}`, since its \
          field `{n}` would have the same JSON field as the constructor's name, `{kindKey}`"
      return key

/-- Returns whether an inductive type with the constructors `ctors` is written as a string. -/
meta def isEnum (ctors : Array Ctor) : Bool :=
  ctors.all (·.fields.isEmpty)

/-- Throws an error unless `indVal` is a type the deriving handlers support. -/
meta def checkSupported (className : Name) (indVal : InductiveVal) : MetaM Unit := do
  if indVal.numIndices > 0 then
    throwError "cannot derive `{className}` for `{indVal.name}`, since it has indices"

/--
Returns the auxiliary definition `name` with the binders `binders`, the result type `type`, and the
body `body`, which is `partial` if any of the types it converts is recursive.
-/
meta def mkAuxDef (ctx : Deriving.Context) (className name : Name) (header : Header)
    (binders : Array (TSyntax ``Parser.Term.bracketedBinder)) (type body : Term) :
    TermElabM Command := do
  let binders := header.binders ++ binders
  if ctx.usePartial || ctx.typeInfos.any (·.isRec) then
    let body ← mkLet (← mkLocalInstanceLetDecls ctx className header.argNames) body
    `(partial def $(mkIdent name):ident $binders:bracketedBinder* : $type := $body)
  else
    `(def $(mkIdent name):ident $binders:bracketedBinder* : $type := $body)

/-- Returns a `match` alternative for `ctor` that binds its fields to `vars`. -/
meta def mkCtorAlt (indVal : InductiveVal) (ctor : Ctor) (vars : Array Ident) (rhs : Term) :
    TermElabM (TSyntax ``Parser.Term.matchAlt) := do
  let params := Array.replicate indVal.numParams (← `(_))
  `(Parser.Term.matchAltExpr| | @$(mkIdent ctor.val.name):ident $params:term* $vars:ident* => $rhs)

meta def mkToJsonBody (header : Header) (indVal : InductiveVal) : TermElabM Term := do
  let toJson := mkCIdent `Lithe.ToJson.toJson
  let obj := mkCIdent `Lithe.Json.obj
  let str := mkCIdent `Lithe.Json.str
  let target := mkIdent header.targetNames[0]!
  if isStructure (← getEnv) indVal.name then
    let fields :=
      getStructureFieldsFlattened (← getEnv) indVal.name (includeSubobjectFields := false)
    let entries ← fields.mapM fun field =>
      `(($(quote (fieldKey field)), $toJson:ident $(mkIdent (header.targetNames[0]! ++ field))))
    return ← `($obj:ident #[$entries,*])
  let ctors ← getCtors indVal
  let alts ← ctors.mapM fun ctor => do
    let vars ← ctor.fields.mapM fun _ => return mkIdent (← mkFreshUserName `a)
    let rhs ← if isEnum ctors then
      `($str:ident $(quote ctor.kind))
    else
      let keys ← ctor.fieldKeys `Lithe.ToJson
      let mut entries := #[← `(($(quote kindKey), $str:ident $(quote ctor.kind)))]
      for key in keys, var in vars do
        entries := entries.push (← `(($(quote key), $toJson:ident $var)))
      `($obj:ident #[$entries,*])
    mkCtorAlt indVal ctor vars rhs
  `(match $target:ident with $alts:matchAlt*)

meta def mkFromJsonBody (indVal : InductiveVal) (v : Ident) : TermElabM Term := do
  let fromJson := mkCIdent `Lithe.FromJson.fromJson?
  let getField := mkCIdent `Lithe.Json.getField
  let expectObject := mkCIdent `Lithe.Json.expectObject
  let unknownKind := mkCIdent `Lithe.Json.unknownKind
  if isStructure (← getEnv) indVal.name then
    let fields :=
      getStructureFieldsFlattened (← getEnv) indVal.name (includeSubobjectFields := false)
    let fieldIds := fields.map mkIdent
    let args ← fields.mapM fun field => `((← $getField:ident $v $(quote (fieldKey field))))
    return ← `(do
      $expectObject:ident $v
      return { $[$fieldIds:ident := $args],* })
  let ctors ← getCtors indVal
  let kinds : Array Term := ctors.map (quote ·.kind)
  let alts ← ctors.mapM fun ctor => do
    let params := Array.replicate indVal.numParams (← `(_))
    let keys ← ctor.fieldKeys `Lithe.FromJson
    let args ← keys.mapM fun key => `((← $getField:ident $v $(quote key)))
    let rhs ← `(do return @$(mkIdent ctor.val.name):ident $params:term* $args:term*)
    `(Parser.Term.matchAltExpr| | $(quote ctor.kind):str => $rhs)
  let kind ← if isEnum ctors then
    `(($fromJson:ident $v : Except String String))
  else
    `(do $expectObject:ident $v; ($getField:ident $v $(quote kindKey) : Except String String))
  let kindVar := mkIdent `kind
  let m ← `(match $kindVar:ident with
    $alts:matchAlt*
    | _ => $unknownKind:ident #[$kinds,*] $kindVar)
  `(do let $kindVar:ident ← $kind:term; $m:term)

meta def mkToJsonInstance (declName : Name) : TermElabM (Array Command) := do
  let className := `Lithe.ToJson
  let ctx ← mkContext className "toJson" declName
  let mut defs := #[]
  for indVal in ctx.typeInfos, name in ctx.auxFunNames do
    checkSupported className indVal
    let header ← mkHeader className 1 indVal
    let body ← mkToJsonBody header indVal
    defs := defs.push (← mkAuxDef ctx className name header #[] (mkCIdent `Lithe.Json) body)
  return #[← `(mutual $defs:command* end)] ++ (← mkInstanceCmds ctx className #[declName])

meta def mkFromJsonInstance (declName : Name) : TermElabM (Array Command) := do
  let className := `Lithe.FromJson
  let ctx ← mkContext className "fromJson" declName
  let mut defs := #[]
  for indVal in ctx.typeInfos, name in ctx.auxFunNames do
    checkSupported className indVal
    let header ← mkHeader className 0 indVal
    let v := mkIdent `v
    let binder ← `(Parser.Term.bracketedBinderF| ($v : $(mkCIdent `Lithe.Json)))
    let type ← `(Except String $(← mkInductiveApp indVal header.argNames))
    let body ← mkFromJsonBody indVal v
    defs := defs.push (← mkAuxDef ctx className name header #[binder] type body)
  return #[← `(mutual $defs:command* end)] ++ (← mkInstanceCmds ctx className #[declName])

/-- Returns a deriving handler that elaborates the commands `mkInstance` returns for each type. -/
meta def mkHandler (mkInstance : Name → TermElabM (Array Command)) (declNames : Array Name) :
    CommandElabM Bool := do
  if declNames.isEmpty || !(← declNames.allM isInductive) then
    return false
  for declName in declNames do
    (← liftTermElabM (mkInstance declName)).forM elabCommand
  return true

meta initialize
  registerDerivingHandler `Lithe.ToJson (mkHandler mkToJsonInstance)
  registerDerivingHandler `Lithe.FromJson (mkHandler mkFromJsonInstance)

end Lithe.Json.Deriving
