# lithe

A UI library for [LeanScript](https://leanscript.org/), which compiles Lean to JavaScript.

```lean
import Lithe

open Lithe

inductive Msg where
  | increment
  | decrement

def update : Msg → Nat → Nat × Cmd Msg
  | .increment, n => (n + 1, .none)
  | .decrement, n => (n - 1, .none)

def view (count : Nat) : Html Msg :=
  <main>
    <button onclick={Msg.decrement}>−</button>
    <span class={cls "zero" (count == 0)}>{count}</span>
    <button onclick={Msg.increment}>+</button>
  </main>

def main : IO Unit :=
  ({ init := (0, .none), update, view } : App Nat Msg).mountById "app"
```

Apps are pure: `update` and `view` describe state changes, effects, and the page as data. That means you can evaluate views with `#eval`, and prove things about your app.

Markup is checked at compile time, and compiles to static HTML with dynamic holes, so updates only compare what can change.

`examples/todo` is a complete app. It's experimental, as LeanScript itself is.

## Development

With [elan](https://github.com/leanprover/elan) and [pnpm](https://pnpm.io) installed, or in the Nix dev shell (`nix develop`, or `direnv allow`):

```sh
pnpm install
pnpm test          # The macro tests, and DOM tests in jsdom.
pnpm test:browser  # The todo example in Chrome.
pnpm bench         # The benchmark in Chrome. Add `--profile` for a breakdown.
```

[`docs/design.md`](docs/design.md) has the design, and the reasons for it.
