import Lithe
import Counter

open Lithe

/-! The client, which LeanScript compiles. It replaces the server's page with a live one. -/

def app : App Nat Msg where
  init := (initial, .none)
  update msg n := (update msg n, .none)
  view := view

def main : IO Unit :=
  app.mountById "app"
