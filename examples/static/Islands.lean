module

public import Lithe.Core

open Lithe

/-! The parts of the site that are interactive, which the generator and the client share. -/

public section

namespace Theme

/-- The changes that the theme switcher can ask for. -/
inductive Msg where
  /-- The browser's theme is known, and is dark or not. -/
  | loaded (dark : Bool)
  | toggle

/--
Returns the theme switcher, where `dark?` is whether the theme is dark, or `none` if that's unknown,
as it is when the site is built. It's hidden then, as without JS it can't do anything.
-/
def view (dark? : Option Bool) : Html Msg :=
  <button id="theme-switcher" type="button" hidden={dark?.isNone} onclick={Msg.toggle}>
    {match dark? with
      | some true => "Use the light theme"
      | some false => "Use the dark theme"
      | none => "Switch theme"}
  </button>

end Theme

/-- A term in the glossary. -/
structure Term where
  name : String
  definition : String
  deriving ToJson

namespace Filter

/-- The state of the glossary's filter. -/
structure Model where
  terms : Array Term
  query : String := ""
  /-- Whether JS is running. The search box is hidden otherwise, as it can't do anything. -/
  live : Bool := false

/-- The changes that the filter can ask for. -/
inductive Msg where
  | search (query : String)

/-- Returns the terms whose names contain the query, ignoring case. -/
def Model.matching (m : Model) : Array Term :=
  let query := m.query.trimAscii.toString.toLower
  m.terms.filter fun term => (term.name.toLower.splitOn query).length > 1 || query.isEmpty

/-- Returns the glossary for `m`. -/
def view (m : Model) : Html Msg :=
  let terms := m.matching;
  <div>
    <input id="filter" type="search" placeholder="Filter by name" aria-label="Filter terms by name"
      hidden={!m.live} value={m.query} oninput={Msg.search} />
    <p id="filter-count">{terms.size} of {m.terms.size} terms</p>
    <dl>
      {Html.keyed <| terms.map fun term =>
        (term.name, <div><dt>{term.name}</dt><dd>{term.definition}</dd></div>)}
    </dl>
  </div>

end Filter
