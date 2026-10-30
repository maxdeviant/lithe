# Todo list

A todo list written with Lithe. You can add items, check them off, remove them, and clear the completed ones.

- `Todo/Model.lean` has the app's state, the updates to it, and a couple of theorems about them.
- `Todo/View.lean` has the page, in markup.
- `App.lean` is the entry point, which `index.html` loads directly.

## Running

```sh
pnpm install
pnpm dev
```
