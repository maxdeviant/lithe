module

public import Lithe.Cmd
public import Lithe.Html
public import Lithe.Json.Deriving
public import Lithe.Render
public import Lithe.Subscription
public import Lithe.Syntax

/-!
The part of Lithe that has no JS dependencies, which programs for both native Lean and LeanScript can
import. `Lithe` adds what runs an app in the browser, and only LeanScript can link it.

It's a module so that native programs can be modules too, which keeps the compiler out of them.
-/
