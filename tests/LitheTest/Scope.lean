import Lithe.Syntax

/-!
Checks that markup only affects files that `open Lithe`. Otherwise `</` would be a token here, which
would stop this from parsing as `<` followed by a comment.
-/

example (a b : Nat) : Prop := a</- comment -/b
