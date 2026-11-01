module

import Islands

open Lithe

/-! The generator, which is a native program. It writes each page of the site as a file. -/

/-- The terms in the glossary, the first of which has characters to escape in HTML and in JSON. -/
def terms : Array Term := #[
  { name := "Hydration", definition := "Making a page from a server <or a build> interactive without replacing it." },
  { name := "Island", definition := "An interactive part of a page that's otherwise static." },
  { name := "Template", definition := "The static HTML of some markup, with the paths of its holes." },
  { name := "Hole", definition := "A place in a template for what changes." }
]

/-- Applies the saved theme. It's inline in the `head`, so the page doesn't show another theme first. -/
def applySavedTheme : String := "try {
  const theme = localStorage.getItem('theme');
  if (theme === 'light' || theme === 'dark') {
    document.documentElement.dataset.theme = theme;
  }
} catch {}"

/-- Returns the element with the ID `id` that holds `view`, whose messages only matter to a client. -/
def island (id : String) (view : Html Msg) : Html Unit :=
  .elem "div" #[.value "id" (.str id)] #[view.map fun _ => ()]

/-- Returns a `script` element with `attrs` and the content `text`, which markup can't have a hole for. -/
def scriptWith (attrs : Array (Attr Unit)) (text : String) : Html Unit :=
  .elem "script" attrs #[.text text]

/--
Returns the document for a page, which loads the client from `client`. Markup can't have `html`,
`head`, or `body`, as an app doesn't render those, or a hole in `title`, so they're built directly.
-/
def document (client pageTitle : String) (content : Html Unit) : String :=
  let html : Html Unit := .elem "html" #[.value "lang" (.str "en")] #[
    .elem "head" #[] #[
      <meta charset="utf-8" />,
      <meta name="viewport" content="width=device-width, initial-scale=1" />,
      .elem "title" #[] #[.text pageTitle],
      <link rel="icon" href="data:," />,
      <link rel="stylesheet" href="/style.css" />,
      scriptWith #[] applySavedTheme,
      <script type="module" src={client}></script>
    ],
    .elem "body" #[] #[
      <header>
        <nav><a href="/">Home</a> <a href="/glossary/">Glossary</a></nav>
        {island "theme" (Theme.view none)}
      </header>,
      <main>{content}</main>
    ]
  ];
  s!"<!doctype html>{html.render}\n"

def home : Html Unit :=
  <section>
    <h1>A static site</h1>
    <p>This page is a file that a Lean program wrote. The theme switcher is the only part of it that runs in a browser.</p>
  </section>

def glossary : Html Unit :=
  <section>
    <h1>Glossary</h1>
    {island "glossary" (Filter.view { terms })}
    {scriptWith #[.value "id" (.str "terms"), .value "type" (.str "application/json")] (Json.encode terms)}
  </section>

/-- Returns the path of the client's script in Vite's manifest, `manifest`. -/
def clientPath (manifest : String) : Except String String := do
  let json ← Json.parse manifest
  match (json.get? "Client.lean").bind (·.get? "file") with
  | some (.str file) => return s!"/{file}"
  | _ => throw "the manifest has no script for Client.lean"

/-- Writes `content` to `path`, creating its parent directories as needed. -/
def writePage (path : System.FilePath) (content : String) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path content

/-- Writes the pages into `dist`, which already has the client's build. -/
public def main : IO Unit := do
  let dist : System.FilePath := "dist"
  let client ← IO.ofExcept (clientPath (← IO.FS.readFile (dist / ".vite" / "manifest.json")))
  writePage (dist / "index.html") (document client "A static site" home)
  writePage (dist / "glossary" / "index.html") (document client "Glossary & terms" glossary)
