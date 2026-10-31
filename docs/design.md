# Design notes

Decisions and constraints to keep in mind while working on Lithe, with the reasons for them.

## Architecture

Lithe follows the Elm architecture. An `App` has a pure `update` and a pure `view`, effects are data (`Cmd`), and `Html` knows nothing about the DOM. Views can therefore be evaluated with `#eval`, tested, and reasoned about in proofs, and server rendering stays possible.

Message types are unconstrained, so `Html (Model → Model)` works too. `App.simple` runs an app whose messages are the state changes themselves.

| Module | Role |
|---|---|
| `Lithe.Core` | Everything below that has no JS dependencies, for code that native Lean also compiles. |
| `Lithe.Html` | The pure description of a page. Has no JS imports. |
| `Lithe.Syntax` | The markup macro. Runs only at compile time. |
| `Lithe.Render` | Rendering `Html` to a string. |
| `Lithe.Json` | JSON, and the deriving handlers for it. |
| `Lithe.Cmd` | Effects as data. |
| `Lithe.Subscription` | Outside events as data. |
| `Lithe.Dom` | Mounting, patching, and event delegation. |
| `Lithe.Hydrate` | Adopting a page that `Html.render` wrote. |
| `Lithe.Subscription.Sources` | The built-in sources of outside events, such as timers. |
| `Lithe.App` | The update and render loop. |

## Native Lean

Lithe has two targets. `Lithe` is for LeanScript, and `Lithe.Core` is for code that both targets compile, such as the view of a page that a native server renders and a client then runs.

**What breaks only shows up when linking.** `@[extern js inline]` compiles to a call to a symbol that nothing defines in a native program, so `#eval` and building oleans both work, and `import Lithe` fails later with undefined symbols from `Js.Value`. So `tests/LitheNativeTest.lean` is a native program, which `pnpm test` links and runs, and `examples/server` is another.

**An extern that a view needs has a native side as well**, as in `@[extern c inline "lean_io_result_mk_ok(lean_box(0))" js inline "..."]`. LeanScript takes the `js` entry and native Lean takes the `c` one. `ElementHandle.focus` does this so that `Action.focus` is in `Lithe.Core`. It does nothing, as nothing runs actions natively.

**Subscriptions are split.** The type and `Subscription.source` are data, so they're in `Lithe.Core`, and a shared module can define `subscriptions` with sources of its own. The built-in sources call the browser, so a function that uses `Subscription.every` belongs on the client.

**Native programs should be modules, all the way from their root.** Each module gets a runtime initializer and a combined one that also covers what its imports use at compile time. A module's runtime initializer only calls those of its imports, but code that isn't a module calls the combined ones, which reach `initialize_Lean` through `Lithe.Syntax`, so the linker can't remove the compiler. A program that shows markup was 101 MB and took 21 ms to start like that, compared with 1.2 MB and 2.4 ms as modules. A program that isn't a module still works, and is only larger. This doesn't apply to LeanScript, which only includes what's reachable. As a module can only import modules, everything in `Lithe.Core` has to be one. `pnpm test` checks the size of its native program.

## Constraints from LeanScript

**JS callbacks freeze what they capture.** `toJs` on a function marks everything reachable from it as persistent, which permanently disables in-place updates of those values. It isn't a leak, as JS garbage collection still applies. In a spike with a 200,000-element array, 2,000 updates took 7 ms with no callback, 6 ms with a callback that captured the `IO.Ref`, and 5,923 ms with one that captured the array itself. So:

- There is one listener per phase at the root, created once. Rendering never creates JS functions.
- Handlers are Lean closures in a table that only Lean reads.
- Handlers should capture IDs, not the model. The previous tree is alive while `update` runs, so a handler that captures the model should force a copy on each update. This is inferred, not measured.

**Compile-time code must be `meta`.** A plain `import Lean` puts the compiler's initializers in the program, and the build fails on missing externs. `Lithe.Syntax` uses `public meta import Lean` and a `public meta section`, as `Js.Deriving` does. `Lithe.Html` is a module because `Lithe.Syntax` imports it.

**Tasks can't be canceled.** `IO.cancel` does nothing, so `Cmd.latest` drops the results of superseded effects, but those effects still run to completion.

**Editing any Lean file reloads the page.** The Vite plugin has no hot module replacement, so app state is lost on each edit.

## Markup

Elements compile to a `Template`, which holds static HTML and the path to each hole. `Html.elem` remains for trees that aren't known at compile time, such as a Markdown renderer. Comparing holes instead of whole trees was about 3x faster in a spike on Node, without DOM work.

**Paths have to match what the HTML parser builds.** The macro therefore rejects anything the parser would restructure: `tr` directly in `table`, block elements in `p`, nested `a`, text in `table`, and so on. It also expands `<div />` to `<div></div>`, because the parser ignores `/>`, and adds a newline at the start of `pre`, where the parser drops one. If a path ever points to the wrong node, look for a parser rule that is missing from these checks.

**Attribute checking is semi-strict.** Tags, attributes, and events are checked against generated tables, from `scripts/generate-html-data.js`. `data-*` and `aria-*` are always allowed, and custom elements (with a `-` in the tag name) accept anything.

**Whitespace** follows Svelte and JSX: whitespace containing a newline at either end of some text goes away, and other newlines collapse to a space. Whitespace with no newline, such as in `{a} {b}`, is kept. `pre`, `textarea`, `listing`, `script`, and `style` are left alone.

**Text is HTML**, so entities such as `&nbsp;` work. To write a literal brace, use a hole: `{"{"}`.

**Comments are Lean's.** Among children, a comment goes in a hole, as in `{/- note -/}`, and between attributes it needs no hole. They nest, so commenting out markup always works, and they never reach the page. The text on either side of one is joined before whitespace is handled, as if the comment weren't there, because it becomes a single DOM node. HTML comments are an error that suggests this form. A bare `-- note` among children stays text, as text may contain anything that looks like Lean.

**`value` on `select` and `textarea` only works in a hole.** They have the property but not the attribute, so a static `value` is an error rather than being silently ignored.

**SVG** is markup that the macro follows into a different set of rules, from the moment it sees `svg`:

- Tags and attributes are checked against tables for SVG, in which case matters, so `viewBox` passes and `viewbox` doesn't. The HTML parser corrects the case of what it reads, but holes use `setAttribute`, and only the table stops a wrong name from having no effect there. Names with a colon, such as `xlink:href`, can't be parsed, so use `href`.
- HTML isn't allowed directly in SVG, as tags such as `div` make the parser leave SVG altogether. Inside `foreignObject` the content is HTML again, and most of the parser's restructuring stops at that element, so `div` in `foreignObject` in `p` is fine. `a` and `form` are the exceptions, as the parser finds those anywhere.
- `/>` really does close elements in SVG, but it's still written out as a closing tag, so that there is one form to emit. Void elements and raw text don't apply, except that `title`, `desc`, `style`, and `script` only take text and holes.

**Markup whose root is only an SVG element**, such as a `rect` in a helper function, is parsed inside a temporary `svg`, as otherwise the parser would make an unknown HTML element. That's what `Template.svg` is for. It's decided by the tag, so a root that is also HTML (`a`, `title`, `style`, or `script`) stays HTML, and has no effect in SVG. Wrap it in `<g>` for the SVG one. As with HTML, what goes in a hole isn't checked against what's around it, so nothing catches this at compile time. `Html.elem` has no such problem, as it creates its element knowing the parent. `math` is still rejected, as it would need the same work.

**`class` has no directive.** Svelte now advises against `class:`, so `class` takes a value like any other attribute: `class={#["row", cls "done" t.done]}`.

### Parsing traps

These were all found by testing, and each has a test in `tests/LitheTest/Syntax.lean`.

- The element parser is at `lead` precedence. At `max`, `a < b` is read as `a` applied to an element, and fails. The cost is that `f <div />` needs parentheses.
- The tokens that end tags (`>`, `/>`, and `}` in a child hole) don't consume whitespace. Otherwise text like ` -- hello` is treated as a Lean comment, and the space in `{a} {b}` is lost.
- Text is parsed outside of the `markupChild` category, as a category parser can't start at whitespace.
- The syntax is `scoped`, so `</` is only a token in files that `open Lithe`.
- `ToChild (Html Msg) Msg` and `ToHandler Msg Msg` are default instances. Otherwise elements nested in a lambda in a hole get stuck on an unknown `Msg`. The first has a higher priority, so that the message type comes from the enclosing markup before `oninput={Msg.set}` can make `String → Msg` the message type.

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

**Focus follows from keys.** There's no effect that focuses an element, as it wouldn't know whether the element has been rendered yet. To focus an input again after a change, make it the only item of a keyed list whose key changes, so that a new element runs `Action.focus`.

**Actions** run once, after their element is in the page, and don't rerun if the action changes between renders. Their syntax is `use={action}` rather than Svelte's `use:action`, as this allows any expression without special parsing.

## Rendering to a string

`Html.render` returns the HTML for a description, which parses to the same page as mounting it, as `tests/dom/Random.lean` and `tests/dom/Render.lean` check. It has no JS imports, so it also works in `#eval`.

**The macro records where each hole goes**, as byte offsets in `Template.sites`. Working it out again from the HTML would take a second parser that has to agree with the first.

**Escaping happens at the boundary.** Static HTML is what the author wrote and goes through as is, so `&nbsp;` works, while anything from a hole is escaped. Text in raw text elements such as `script` can't be escaped, so `</` becomes `<\/` there, and names that `Html.elem` got at run time are dropped if they could add markup, as the DOM would reject them too.

**Live properties** become what sets their initial state: `value` and `checked` are attributes, `value` on `textarea` is its content, and `value` on `select` adds `selected` to the first matching `option`, found by scanning the rendered content. `indeterminate` has no form in HTML, so it's dropped. A `select` whose value matches no option has none selected when mounted, but HTML can't say that, so the browser selects the first.

**Attributes can't be repeated in markup**, as `setAttribute` makes the last one win and the HTML parser keeps the first. `Html.elem` isn't checked.

**Holes can still restructure the output.** A hole's content is added directly to the DOM when mounting, so `<p>{<div />}</p>` works, but the same HTML makes the parser close the `p`. The macro can't see this, as holes aren't checked against what's around them.

## Hydration

`App.hydrate` starts an app on a page that `Html.render` wrote, and keeps its nodes, so that nothing flickers and nothing loses its state. In a benchmark of rows like those in `bench`, including layout, it took 8.6 ms for 1,000 rows in Chrome where replacing them took 24 ms, and 75 ms for 10,000 where replacing them took 234 ms. It was about 2.4 times as fast in Firefox and 3.4 times in WebKit. It adds about 5.5 KB gzipped to a client that uses it, and nothing to one that doesn't, other than a small function that mounting shares with it.

**The HTML has no markers.** The client runs the same view, so it knows what every node has to be. All that the page can't show is where text from different places was merged, and that's found from the length of the text that's expected, with `splitText`. So rendering adds no bytes, and a proxy that strips comments can't break a page. The comment that patching needs after each hole is added by the client. `tests/dom/Hydrate.lean` checks that the result is the same as mounting, down to how text is divided, and that it then patches in the same way.

**Differences are handled by what they affect.** Text or structure that isn't as expected means the page and the view disagree about where things are, so the whole root is replaced, with a message on the console. Attributes outside of holes aren't compared, as they're the same markup on both sides. Attributes in holes are corrected in place, and only if they differ, as setting `src` again restarts loading. Handlers and actions are only added, so nothing has run by the time a difference is found, and replacing needs no undoing.

**The model wins.** Live properties are written as in patching, so what the user typed before the client started is overwritten, and earlier clicks are lost. Replaying those through their handlers is possible later, as the description says which handler each field has.

**An empty root is mounted,** which isn't a mismatch, so a client running on its own with `pnpm dev` needs no other code path. Whitespace at either end of the root is ignored unless the view has text there, as a template's formatting can put it there.

**What parsers do decides most of the details,** and `tests/browser/dom.js` runs these checks in real browsers because of that. Each of these was found by testing:

- `\r\n` in text or an attribute becomes `\n`, unless it's written as a character reference, which `Html.render` now does.
- WebKit splits long text into several nodes, so the root is normalized first.
- `noscript` is text in a page with scripting, but in a template it's elements in Chrome and WebKit, and text in Firefox. So its content is never compared, and it can't have holes.
- NUL becomes U+FFFD, and text in `style` and similar elements can't be escaped, so `Html.render` breaks up `</` there. The first leads to replacing the root, and the second is expected.

**A view has to give the same result on both targets,** or the root is replaced. The results of `toString` on floats and the order of hash maps were the same in a small sample, and `USize` is the one known difference, at 32 bits in LeanScript.

**The model travels as JSON in a `script` element.** `jsonScript` writes one on the server, and `readJsonScript?` reads it with `JSON.parse` and `FromJs`. A module that both sides import can't derive `FromJs`, as that needs JS, so the client uses `deriving instance`. An app builds its `init` from what that returns, so `App` has no part in this.

## JSON

`Lithe.Json` exists because a native program can't use `Lean.Data.Json` without paying for all of Lean. Lean's C emitter makes a module call `lean_initialize` if any module in its run-time imports has a name that starts with `Lean`, and that function refers to `initialize_Lean`, so the linker keeps the whole compiler. It doesn't matter how small the import is or whether the program is a module: `import Lean.Data.Name` alone takes a program from 1 MB to 101 MB. This is [lean4#5274](https://github.com/leanprover/lean4/issues/5274). `Lithe.Json` adds 0.3 MB to the native test, whose size `pnpm test` checks.

**The form is that of `Js.Deriving`,** rather than that of Lean's own handlers. Enums are strings, other inductive types are objects with a `kind` field, and `none` is `null`. So a client can read what a server writes with `JSON.parse` and `FromJs`, and `tests/dom/Json.lean` checks that it can.

**Clients should read with `JSON.parse` and `FromJs` where they can, which is what `readJsonScript?` does.** For an array of records, it added 1.8 KB gzipped to a bundle where `Json.decode` added 11.2 KB, and it was 3 to 9 times as fast. The limits are that `FromJs` needs numbers to be safe integers or floats, and has no strings for infinities and `NaN`. `Json.decode` is for native programs, and for values that those limits rule out. For comparison, `Lean.Data.Json` added 33.7 KB to a client.

**Both targets have to agree,** as a client has to compute the same page as the server. `tests/LitheTest/JsonCases.lean` runs under both, and `pnpm test` compares what they write and read, down to the bits of floats. In the browser build, the results are also checked against `JSON.parse` and `Number`, which share nothing with this code.

**Floats read back exactly.** `Lean.Data.Json` writes them through `toString`, which keeps 6 decimals, and that would change what a view shows. Here they have the fewest digits that read back as the same bits, which are the digits that JS writes, and reading rounds correctly, with no dependency on either platform's conversions. Infinities and `NaN` are strings, as JSON has no numbers for them. `-0` is a number, and `Json.Number` keeps its sign apart for that reason.

**Numbers keep their exponent apart,** so `1e1000000` costs nothing to read. Only `toNat?` and `toInt?` expand one, up to an exponent of 4096.

**`<` is always escaped,** as `\u003c`, so `compress` is safe to put in a `script` element without a separate form for that. `<` can only be in strings, where this means the same thing.

**Nesting is limited to 128 levels,** as otherwise input could exhaust the stack, which can't be caught in Lean. The deepest that worked from the top of the stack was 462 in Chrome, 2,343 in Firefox, and 6,787 in WebKit, for objects, which use more stack than arrays.

**Objects are arrays of fields,** which keep their order and need no tree map in the bundle. Looking up a field is linear, and the last of a repeated field counts, as in `JSON.parse`.

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

`node bench/run.js --profile` runs js-framework-benchmark's operations in Chrome. These are the results from 2026-10-31, with LeanScript 0.2.0 on one machine, in milliseconds:

| Operation | Script | With layout | Slowest with layout |
|---|---:|---:|---:|
| Create 1,000 rows | 16.4 | 29.4 | 34.9 |
| Replace 1,000 rows | 18.5 | 30.8 | 32.4 |
| Update every 10th row of 1,000 | 6.1 | 9.6 | 16.5 |
| Select a row of 1,000 | 6.0 | 6.0 | 7.9 |
| Swap 2 rows of 1,000 | 9.9 | 11.1 | 20.0 |
| Remove a row of 1,000 | 10.3 | 11.5 | 18.9 |
| Append 1,000 rows to 1,000 | 22.7 | 36.3 | 41.2 |
| Clear 1,000 rows | 6.2 | 6.3 | 7.2 |
| Create 10,000 rows | 133.4 | 273.5 | 314.0 |
| Update every 10th row of 10,000 | 38.9 | 76.6 | 87.6 |

**Conclusion: no change is justified.** The updates to existing rows of 1,000 meet the budget at the median, although the slowest runs of update, swap, and remove go over it. Creating rows misses it, but the profile doesn't point to the Lean-to-DOM boundary: most of the time is split between native DOM work, which moving to JS can't remove, and the runtime's bookkeeping, such as reference counting and allocation.

Ideas to try if the numbers become a problem, in rough order of expected value:

- Look up parsed templates by object rather than by hashing the key. `hashBytes` is about 10% of the self time when creating rows.
- Skip the view of unchanged rows with a memoizing `lazy` node. Note that a memo that retains part of the model stops that part from being updated in place.
- Find holes with `firstChild` and `nextSibling` rather than `childNodes[i]`.

## Not in the first version

Replaying what the user did before hydrating, streaming, `component` syntax, scoped CSS, transitions, MathML, and hot reload that preserves state. A patcher proof is also out, with randomized tests in `tests/dom/Random.lean` standing in for it.
