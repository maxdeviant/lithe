import Lithe
import Islands

open Lithe

/-! The client, which LeanScript compiles. It makes the islands on a page interactive. -/

deriving instance FromJs for Term

/-- Returns whether the page's theme is dark. The saved theme was applied before the page was shown. -/
@[extern js inline "(document.documentElement.dataset.theme ?? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')) === 'dark' ? 1 : 0"]
opaque isDark : BaseIO Bool

/-- Applies the dark or light theme and saves it, or clears what's saved if it's the system's theme. -/
@[extern js inline "(() => { const root = document.documentElement; const theme = #1 !== 0 ? 'dark' : 'light'; const system = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'; if (theme === system) { delete root.dataset.theme; } else { root.dataset.theme = theme; } try { if (theme === system) { localStorage.removeItem('theme'); } else { localStorage.setItem('theme', theme); } } catch {} return 0; })()"]
opaque applyDark (dark : Bool) : BaseIO Unit

/--
The theme switcher. Only the browser knows the theme, so this starts from what the page was built
from, for it to match the page, and then finds out with a command.
-/
def themeApp : App (Option Bool) Theme.Msg where
  init := (none, Cmd.attempt isDark fun result => .loaded (result.toOption.getD false))
  update msg dark? := match msg with
    | .loaded dark => (some dark, .none)
    | .toggle =>
      let dark := !dark?.getD false
      (some dark, Cmd.attempt (applyDark dark) fun _ => .loaded dark)
  view := Theme.view

/-- The glossary's filter, for `terms`. -/
def filterApp (terms : Array Term) : App Filter.Model Filter.Msg where
  init := ({ terms, live := true }, .none)
  update msg m := match msg with
    | .search query => ({ m with query }, .none)
  view := Filter.view

def main : IO Unit := do
  themeApp.hydrateById "theme"
  if let some terms ← (readJsonScript? "terms" : IO (Option (Array Term))) then
    (filterApp terms).hydrateById "glossary"
