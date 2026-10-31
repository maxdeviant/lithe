# Server

A counter whose page comes from a native Lean server, and that LeanScript then makes interactive.

- `Counter.lean` has the state and the page, and imports `Lithe.Core`, so both sides can use it.
- `Server.lean` is a native program, which uses `Html.render` to put the page in its response.
- `App.lean` is the client, which `index.html` loads directly, and imports all of `Lithe`.

## How it works

**The page works before any JS runs**, so it's on screen as soon as the HTML arrives, and it's there for anything that doesn't run JS at all.

**The client replaces the page rather than hydrating it**, as Lithe has no hydration yet. It builds the same page again from the same `initial` state, and takes over the element it's in.

**Actions are the part of a view that needs care.** Lean only links a native program if everything it refers to has a native implementation, so a shared view can use `Action.focus`, but an action of your own has to give its extern a native side too. It's never run there, as rendering leaves actions out:

```lean
@[extern c inline "lean_io_result_mk_ok(lean_box(0))" js inline "(#1.showModal(), 0)"]
opaque showModal (dialog : @& ElementHandle) : BaseIO Unit
```

## Running

```sh
pnpm install
pnpm build
lake exe server
```

Then open <http://localhost:3000/>. `pnpm dev` runs the client alone, without the server's page. The server's arguments are the port and the directory of the client's build.

Open `examples/server` as its own project in your editor, as it's a separate Lake package.
