# Static

A site whose pages are files from a native Lean program, with two small interactive parts that LeanScript makes live.

- `Islands.lean` has the views of the interactive parts, and is a module that imports `Lithe.Core`, so both sides can use it.
- `Site.lean` is a native program that writes the pages. The rest of each page's content is only here, so none of it ends up in the client.
- `Client.lean` is the client, which hydrates the parts that are on the page. It's the same script on every page.

## How it works

**The client's name comes from Vite.** Vite builds the client first, under a name with its fingerprint, and the generator finds that name in Vite's manifest. The files in `public` are copied as they are.

**Each island is an app of its own,** with its own root and state. The generator puts each view in an element for the client to find. It uses `Html.map` to give all of a page the same message type, as rendering leaves handlers out.

**A static page can't know what only the browser knows,** so an island has to hydrate with the state that the page was built from, or the page would be replaced. The theme switcher does that, and then finds out the theme with a command in `init`. A difference in an attribute in a hole is the exception, as it's corrected in place, which is how the search box gets to be shown: `filterApp` starts with `live` set.

**The theme has to be applied before the page is shown,** which is too early for a module script, so a small inline script does that.

**Markup doesn't cover the whole document.** It can't have `html`, `head`, or `body`, and can't have holes in `title` or `script`, so `Site.lean` builds those with `Html.elem`.

## Running

```sh
pnpm install
pnpm build
pnpm preview
```

Then open the address that Vite prints. There's no `pnpm dev`, as a client needs the generator's pages to adopt, so run `pnpm build` after a change.

Open `examples/static` as its own project in your editor, as it's a separate Lake package.
