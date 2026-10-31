import Lithe
import Counter

open Lithe

/-! The client, which LeanScript compiles. It makes the server's page live. -/

deriving instance FromJs for Model

/-- Returns the app with the state `model`. -/
def app (model : Model) : App Model Msg where
  init := (model, .none)
  update msg m := (update msg m, .none)
  view := view

/-- `pnpm dev` has no server, and so no state to read or page to adopt, and starts from `initial`. -/
def main : IO Unit := do
  let model ← readJsonScript? "model"
  (app (model.getD initial)).hydrateById "app"
