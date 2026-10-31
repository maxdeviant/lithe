# Kanban

A kanban board written with Lithe, which is large enough to show how the pieces fit together.

- `Kanban/Board.lean` has the data and the operations on it, with proofs about them, and knows nothing about the page.
- `Kanban/Route.lean` has the routes, which go in the URL's hash.
- `Kanban/Browser.lean` has the reads and writes of `localStorage` and the URL.
- `Kanban/Model.lean` has the app's state, and the updates to it.
- `Kanban/View.lean` has the page, in markup.
- `App.lean` has the subscriptions, and is the entry point, which `index.html` loads directly.

## How it works

**Dragging** is the browser's own drag and drop. Each handler captures IDs, and the model holds what's being dragged and where it would land, so nothing reads the event's `dataTransfer`. The drop position is drawn with a shadow, as changing the layout during a drag makes the target jump. Touch screens don't send these events, so cards also have buttons that move them between columns, but only dragging reorders a column.

**Undo** keeps earlier boards in the model, which is all it takes when the board is an ordinary value. Each change copies the arrays that changed, as the history retains the old ones.

**The URL decides which card is open.** A card's title is a plain link, and a subscription reports changes to the hash, so the back button and reloading work without further code.

**The card dialog** is a real `<dialog>`, which an action shows as a modal and closes on removal, which gives focus back. The browser handles Escape, and the `close` event tells the model.

**The chart** in the toolbar is SVG in markup, with each bar written as a `rect` in its own function.

**Saving** is an effect of each change to the board, and a failure appears on the page. Loading happens in `main`, before the app starts, so the page never shows a board that's about to be replaced.

## Running

```sh
pnpm install
pnpm dev
```

Open `examples/kanban` as its own project in your editor, as it's a separate Lake package.
