# Design notes

Decisions and constraints to keep in mind while working on Lithe, with the reasons for them.

## Architecture

Lithe follows the Elm architecture. An `App` has a pure `update` and a pure `view`, effects are data (`Cmd`), and `Html` knows nothing about the DOM. Views can therefore be evaluated with `#eval`, tested, and reasoned about in proofs, and server rendering stays possible.

Message types are unconstrained, so `Html (Model → Model)` works too. `App.simple` runs an app whose messages are the state changes themselves.

| Module | Role |
|---|---|
| `Lithe.Html` | The pure description of a page. Has no JS imports. |
| `Lithe.Syntax` | The markup macro. Runs only at compile time. |
| `Lithe.Dom` | Mounting, patching, and event delegation. |
| `Lithe.Cmd` | Effects as data. |
| `Lithe.Subscription` | Outside events as data. |
| `Lithe.App` | The update and render loop. |

## Constraints from LeanScript

**JS callbacks freeze what they capture.** `toJs` on a function marks everything reachable from it as persistent, which permanently disables in-place updates of those values. It isn't a leak, as JS garbage collection still applies. In a spike with a 200,000-element array, 2,000 updates took 7 ms with no callback, 6 ms with a callback that captured the `IO.Ref`, and 5,923 ms with one that captured the array itself. So:

- There is one listener per phase at the root, created once. Rendering never creates JS functions.
- Handlers are Lean closures in a table that only Lean reads.
- Handlers should capture IDs, not the model. The previous tree is alive while `update` runs, so a handler that captures the model should force a copy on each update. This is inferred, not measured.

**Compile-time code must be `meta`.** A plain `import Lean` puts the compiler's initializers in the program, and the build fails on missing externs. `Lithe.Syntax` uses `public meta import Lean` and a `public meta section`, as `Js.Deriving` does. `Lithe.Html` is a module because `Lithe.Syntax` imports it. `Lithe.Dom` can't be one, as `Js.Dom` isn't.

**Tasks can't be canceled.** `IO.cancel` does nothing, so `Cmd.latest` drops the results of superseded effects, but those effects still run to completion.

**Editing any Lean file reloads the page.** The Vite plugin has no hot module replacement, so app state is lost on each edit.

## Markup

Elements compile to a `Template`, which holds static HTML and the path to each hole. `Html.elem` remains for trees that aren't known at compile time, such as a Markdown renderer. Comparing holes instead of whole trees was about 3x faster in a spike on Node, without DOM work.

**Paths have to match what the HTML parser builds.** The macro therefore rejects anything the parser would restructure: `tr` directly in `table`, block elements in `p`, nested `a`, text in `table`, and so on. It also expands `<div />` to `<div></div>`, because the parser ignores `/>`, and adds a newline at the start of `pre`, where the parser drops one. If a path ever points to the wrong node, look for a parser rule that is missing from these checks.

**Attribute checking is semi-strict.** Tags, attributes, and events are checked against generated tables, from `scripts/generate-html-data.js`. `data-*` and `aria-*` are always allowed, and custom elements (with a `-` in the tag name) accept anything.

**Whitespace** follows Svelte and JSX: whitespace containing a newline at either end of some text goes away, and other newlines collapse to a space. Whitespace with no newline, such as in `{a} {b}`, is kept. `pre`, `textarea`, `listing`, `script`, and `style` are left alone.

**Text is HTML**, so entities such as `&nbsp;` work. To write a literal brace, use a hole: `{"{"}`.

**Comments are Lean's.** Among children, a comment goes in a hole, as in `{/- note -/}`, and between attributes it needs no hole. They nest, so commenting out markup always works, and they never reach the page. The text on either side of one is joined before whitespace is handled, as if the comment weren't there, because it becomes a single DOM node. HTML comments are an error that suggests this form. A bare `-- note` among children stays text, as text may contain anything that looks like Lean.

**`class` has no directive.** Svelte now advises against `class:`, so `class` takes a value like any other attribute: `class={#["row", cls "done" t.done]}`.

### Parsing traps

These were all found by testing, and each has a test in `tests/LitheTest/Syntax.lean`.

- The element parser is at `lead` precedence. At `max`, `a < b` is read as `a` applied to an element, and fails. The cost is that `f <div />` needs parentheses.
- The tokens that end tags (`>`, `/>`, and `}` in a child hole) don't consume whitespace. Otherwise text like ` -- hello` is treated as a Lean comment, and the space in `{a} {b}` is lost.
- Text is parsed outside of the `markupChild` category, as a category parser can't start at whitespace.
- The syntax is `scoped`, so `</` is only a token in files that `open Lithe`.
- `ToChild (Html Msg) Msg` and `ToHandler Msg Msg` are default instances. Otherwise elements nested in a lambda in a hole get stuck on an unknown `Msg`.

Known rough edges, which can't be fixed in the macro:

- An element after a `let` on the next line continues the expression, so `let x := y` followed by `<div>` parses as `y < div`. Lean's parser for `<` can't be removed, so `;` is required, but a parser that only exists to fail explains this.
- `{xs[0]?.map fun x => <p>{x}</p>}` fails, as the element type of `xs[0]?` isn't known soon enough. Annotate it, as in `(xs[0]? : Option String)`, or use `match`.
- `fun s => fun m => ...` as a handler needs its type written out, so handlers that are state functions taking an argument work best as named functions.
- A wrong handler type reports the type class failure, such as `OfNat Unit 42`.

## Patching

**Mounting** clones a parsed template, follows the paths before adding anything (as new nodes shift the indices), fills the holes, and then inserts the root. Content holes come before attribute holes, so that `value` on a `select` is set after its options exist. Content goes before a comment marker, which stays in place as an anchor.

**Patching** works backward through children, so the node to insert before is always known. Templates match if they are the same object or have the same key. Each template is a closed term, so a given call site reuses one object, and the object check usually settles it without comparing strings.

**Keyed lists** are the only form of list that markup accepts: an `Array` in a hole has no `ToChild` instance, so use `Html.forEach`. Moves are minimized with a longest increasing subsequence, so a swap touches two items rather than everything between them. Duplicate keys report to the console, and the extra items get new nodes.

**Live properties** (`value`, `checked`, `selected`, `indeterminate`, and `muted`) are written as properties, and compared to the DOM rather than to the previous hole value, as the user may have changed them. Writing only when they differ is also what keeps the cursor in place while typing.

**Rendering is batched** in a microtask, so several messages in one turn cause one render. An event whose handler sends no message doesn't render, so a controlled input can briefly disagree with the model in that case.

**Events** walk from the target through `parentNode` to the root, reading a slot number stored on each element. Events that don't bubble use a capture-phase listener and go to their target only. That includes `mouseenter` and `mouseleave`, as the browser sends the root's capture listener one event per element.

**Actions** run once, after their element is in the page, and don't rerun if the action changes between renders. Their syntax is `use={action}` rather than Svelte's `use:action`, as this allows any expression without special parsing.

## Subscriptions

An app's optional `subscriptions` function returns the outside events to listen to in a given state, such as a timer that only exists while a stopwatch runs. It's named `Subscription` because `Sub` is ambiguous with Lean's class of that name after `open Lithe`.

**Identity comes from keys.** Functions can't be compared, so each source has a string key, and it keeps running for as long as its key is subscribed. The built-in sources make theirs from their parameters, as in `every:1000`, so changing the interval restarts the timer. Sources with the same key are told apart by position, so two `every 1000` both run.

**Sources sync after each render**, so a batch of messages leads to one sync. Stopping comes first, so that a replacement never overlaps what it replaces.

**Handlers are the same `Handler` as in markup**, and go through a table cell that is updated on each sync. The JS callback only captures the cell, so starting a source once is enough however often its handler changes, and the handler always sees current values. A source's events are `Event` snapshots, as the handler has to stay pure.

**Handlers should capture IDs, not the model.** The previous handler is alive while `update` runs, so a captured model is copied on each update. With a 200,000-element array, updates took about 0.03 ms with a running subscription whose handler captures nothing, and 2.1 ms with one that captures the model. The first number shows that a running subscription doesn't itself stop updates in place.

A source that fails to start logs an error and counts as running, so that it isn't retried on every render. Apps have no way to unmount, so sources run until the state stops asking for them.

## Performance

The rule is that patching stays in Lean unless benchmarking shows both of these:

1. An update misses the 16 ms frame budget.
2. The profile shows the time going to the calls from Lean to the DOM, not to `view` or the diff.

`node bench/run.js --profile` runs js-framework-benchmark's operations in Chrome. These are the results from 2026-10-30, with LeanScript 0.1.0 on one machine, in milliseconds:

| Operation | Script | With layout | Slowest with layout |
|---|---:|---:|---:|
| Create 1,000 rows | 21.8 | 34.3 | 41.7 |
| Replace 1,000 rows | 23.1 | 36.3 | 39.0 |
| Update every 10th row of 1,000 | 7.9 | 11.7 | 16.4 |
| Select a row of 1,000 | 8.0 | 8.0 | 10.2 |
| Swap 2 rows of 1,000 | 14.6 | 15.9 | 24.7 |
| Remove a row of 1,000 | 13.5 | 15.1 | 18.4 |
| Append 1,000 rows to 1,000 | 31.1 | 45.2 | 48.3 |
| Clear 1,000 rows | 6.9 | 6.9 | 9.2 |
| Create 10,000 rows | 181.3 | 321.4 | 349.0 |
| Update every 10th row of 10,000 | 73.4 | 113.5 | 121.6 |

**Conclusion: no change is justified.** The updates to existing rows of 1,000 meet the budget at the median, although close to it in the case of swap and remove. Creating rows misses it, but the profile doesn't point to the Lean-to-DOM boundary: most of the time is split between native DOM work, which moving to JS can't remove, and the runtime's bookkeeping, such as reference counting and allocation.

Ideas to try if the numbers become a problem, in rough order of expected value:

- Look up parsed templates by object rather than by hashing the key. `hashBytes` is about 4% to 8% of the JS self time when creating rows.
- Skip the view of unchanged rows with a memoizing `lazy` node. Note that a memo that retains part of the model stops that part from being updated in place.
- Find holes with `firstChild` and `nextSibling` rather than `childNodes[i]`.
- Upgrade LeanScript, as `main` has inlining work that 0.1.0 doesn't.

## Not in the first version

Server rendering and hydration, `component` syntax, scoped CSS, transitions, SVG, and hot reload that preserves state. A patcher proof is also out, with randomized tests in `tests/dom/Random.lean` standing in for it.

SVG needs skeletons parsed with the right namespace, and a way to create elements in that namespace for `Html.elem`.
