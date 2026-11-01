# Server

A counter whose page comes from a native Lean server, and that LeanScript then makes interactive.

- `Counter.lean` has the state and the page, and is a module that imports `Lithe.Core`, so both sides can use it.
- `Server.lean` is a native program, which uses `Html.render` to put the page in its response.
- `App.lean` is the client, which `index.html` loads directly, and imports all of `Lithe`.

## How it works

**The page works before any JS runs**, so it's on screen as soon as the HTML arrives, and it's there for anything that doesn't run JS at all.

**The client adopts the page rather than replacing it.** `hydrateById` keeps every node that the server sent, and adds the handlers and actions that HTML can't have, so nothing flickers and nothing loses its state.

**The state comes from the server.** Try <http://localhost:3000/?count=5>. `Html.jsonScript` puts the model in the page as JSON, and `readJsonScript?` reads it with `JSON.parse` and `FromJs`, which adds much less to the client than `Json.decode`. `Counter.lean` can't derive `FromJs`, as that needs JS, so `App.lean` does that with `deriving instance`.

**Actions are the part of a view that needs care.** Lean only links a native program if everything it refers to has a native implementation, so a shared view can use `Action.focus`, but an action of your own has to give its extern a native side too. It's never run there, as rendering leaves actions out:

```lean
@[extern c inline "lean_io_result_mk_ok(lean_box(0))" js inline "(#1.showModal(), 0)"]
opaque showModal (dialog : @& ElementHandle) : BaseIO Unit
```

**The native side is all modules**, starting from `Server.lean`, and that's what keeps the server small. Code that isn't a module initializes everything that its imports use at compile time, so importing the markup macro from one would link all of Lean's compiler into the server, which adds about 100 MB.

## Running

```sh
pnpm install
pnpm build
lake exe server
```

Then open <http://localhost:3000/>. `pnpm dev` runs the client alone, which has no page to adopt, so it builds one from `initial`. The server's arguments are the port and the directory of the client's build.

Open `examples/server` as its own project in your editor, as it's a separate Lake package.
