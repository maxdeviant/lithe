import Lithe
import Todo.Model
import Todo.View

open Lithe

def app : App Model Msg where
  init := ({}, .none)
  update msg m := (m.update msg, .none)
  view := view

def main : IO Unit :=
  app.mountById "app"
