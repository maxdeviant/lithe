# Stopwatch

A stopwatch written with Lithe, which shows subscriptions: it only listens to a timer while it's running, and always listens for its keyboard shortcuts.

- `Stopwatch/Model.lean` has the app's state, and the updates to it.
- `Stopwatch/View.lean` has the page, in markup.
- `App.lean` has the subscriptions, and is the entry point, which `index.html` loads directly.

## Running

```sh
pnpm install
pnpm dev
```
