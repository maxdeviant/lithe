import Lithe
import Kanban.Model

open Lithe

/-! The page, in markup. Handlers capture IDs rather than the model, which stays updatable in place. -/

@[extern js inline "(#1.showModal(), 0)"]
opaque showModal (dialog : @& ElementHandle) : BaseIO Unit

@[extern js inline "(#1.close(), 0)"]
opaque closeDialog (dialog : @& ElementHandle) : BaseIO Unit

/-- An action that shows a `dialog` as a modal. Closing it on removal gives focus back. -/
def Action.modal : Action := fun dialog => do
  showModal dialog
  return closeDialog dialog

/-- Returns the message for closing the form for a new card, if `e` asks for that. -/
def cancelOnEscape (e : Lithe.Event) : Option Msg :=
  if e.key == "Escape" then some .cancelAdding else none

/-- Returns the chips for `labels`. -/
def viewLabels (labels : Array Label) : Html Msg :=
  <ul class="labels">
    {Html.forEach labels (·.name) fun l => <li class={s!"label {l.name}"}>{l.name}</li>}
  </ul>

/-- Returns the button that moves `card` to the column `target`, if there is one. -/
def viewMoveButton (card : Card) (target : Option Nat) (label symbol : String) : Html Msg :=
  <button
    aria-label={label}
    disabled={target.isNone}
    onclick={Msg.moveCard card.id (target.getD card.column)}
  >{symbol}</button>

/-- Returns the item for `card`. -/
def viewCard (m : Model) (card : Card) : Html Msg :=
  <li
    class={#[
      "card",
      cls "dragging" (m.dragging == some card.id),
      cls "drop-before"
        (m.dragging.isSome && (m.dropTarget.bind (·.before)) == some card.id)]}
    data-card={card.id}
    draggable="true"
    ondragstart={Msg.dragStart card.id}
    ondragend={Msg.dragEnd}
    ondragover={preventDefault (stopPropagation
      (Msg.dragOver (some { column := card.column, before := some card.id })))}
  >
    <a href={(Route.card card.id).href} draggable="false">{card.title}</a>
    {viewLabels card.labels}
    <div class="card-actions">
      {viewMoveButton card (m.board.columnAt card.column (-1)) "Move left" "←"}
      {viewMoveButton card (m.board.columnAt card.column 1) "Move right" "→"}
    </div>
  </li>

/--
Returns the form for a new card. The input is the only item of a list keyed by the next ID, so that
adding a card makes a new one, whose action focuses it, however the form was submitted.
-/
def viewNewCard (m : Model) : Html Msg :=
  <form class="new-card" onsubmit={preventDefault Msg.submitDraft} onkeydown={cancelOnEscape}>
    {Html.forEach #[m.board.nextId] id fun _ =>
      <input
        aria-label="Title of the new card"
        placeholder="What needs doing?"
        autocomplete="off"
        value={m.draft}
        oninput={Msg.setDraft}
        use={Action.focus}
      />}
    <button>Add</button>
    <button type="button" onclick={Msg.cancelAdding}>Cancel</button>
  </form>

/-- Returns the part of a column that adds a card to it. -/
def viewAdding (m : Model) (column : Column) : Html Msg :=
  if m.adding == some column.id then
    viewNewCard m
  else
    <button class="add-card" onclick={Msg.startAdding column.id}>Add a card</button>

/-- Returns the text that says how many of a column's cards are shown. -/
def countText (shown total : Nat) : String :=
  if shown == total then toString total else s!"{shown} of {total}"

/-- Returns the section for `column`. -/
def viewColumn (m : Model) (column : Column) : Html Msg :=
  let cards := m.board.cardsIn column.id;
  let shown := cards.filter m.shows;
  <section
    class={#[
      "column",
      cls "drop-end" (m.dragging.isSome && m.dropTarget == some { column := column.id, before := none })]}
    data-column={column.id}
    ondragover={preventDefault (stopPropagation
      (Msg.dragOver (some { column := column.id, before := none })))}
    ondrop={preventDefault Msg.drop}
  >
    <header>
      <input
        class="column-name"
        aria-label="Column name"
        value={column.name}
        onchange={Msg.renameColumn column.id}
      />
      <span class="count">{countText shown.size cards.size}</span>
      <button
        aria-label="Move column left"
        disabled={(m.board.columnAt column.id (-1)).isNone}
        onclick={Msg.shiftColumn column.id (-1)}
      >←</button>
      <button
        aria-label="Move column right"
        disabled={(m.board.columnAt column.id 1).isNone}
        onclick={Msg.shiftColumn column.id 1}
      >→</button>
      <button
        aria-label="Remove column"
        disabled={!cards.isEmpty}
        onclick={Msg.removeColumn column.id}
      >×</button>
    </header>
    <ul class="cards">{Html.forEach shown (·.id) (viewCard m)}</ul>
    {viewAdding m column}
  </section>

/-- Returns the toggle for filtering by `label`. -/
def viewFilter (m : Model) (label : Label) : Html Msg :=
  <button
    class={s!"label {label.name}"}
    aria-pressed={toString (m.labelFilter == some label)}
    onclick={Msg.toggleFilter label}
  >{label.name}</button>

/-- Returns the bar for `column`, the `i`th in a chart whose tallest bar has `most` cards. -/
def viewBar (b : Board) (most : Nat) (column : Column) (i : Nat) : Html Msg :=
  let count := (b.cardsIn column.id).size;
  let height := count * 24 / max most 1;
  <rect x={i * 12} y={24 - height} width="10" height={height}>
    <title>{s!"{column.name}: {count}"}</title>
  </rect>

/-- Returns the chart of how many cards each column has. -/
def viewChart (b : Board) : Html Msg :=
  let most := b.columns.foldl (fun n c => max n (b.cardsIn c.id).size) 0;
  <svg
    class="chart"
    role="img"
    aria-label="Cards in each column"
    viewBox={s!"0 0 {b.columns.size * 12} 24"}
  >
    {Html.forEach b.columns.zipIdx (·.1.id) fun (c, i) => viewBar b most c i}
  </svg>

/-- Returns the toolbar. -/
def viewToolbar (m : Model) : Html Msg :=
  <header class="toolbar">
    <h1>Kanban</h1>
    <input
      id="search"
      type="search"
      placeholder="Search cards"
      aria-label="Search cards"
      value={m.search}
      oninput={Msg.setSearch}
    />
    <div class="filters">{Html.forEach Label.all (·.name) (viewFilter m)}</div>
    {viewChart m.board}
    <button id="undo" disabled={m.past.isEmpty} onclick={Msg.undo}>Undo</button>
    <button id="redo" disabled={m.future.isEmpty} onclick={Msg.redo}>Redo</button>
  </header>

/-- Returns the checkbox for `label` in the card dialog. -/
def viewLabelChoice (e : Editor) (label : Label) : Html Msg :=
  <label>
    <input type="checkbox" checked={e.labels.contains label} onchange={Msg.setLabel label} />
    {label.name}
  </label>

/-- Returns the dialog for the open card. The browser closes it on Escape, which `close` reports. -/
def viewEditor (columns : Array Column) (e : Editor) : Html Msg :=
  <dialog id="editor" use={Action.modal} onclose={Msg.closeEditor}>
    <form onsubmit={preventDefault Msg.saveEditor}>
      <label>
        Title
        <input id="editor-title" required autofocus value={e.title} oninput={Msg.setTitle} />
      </label>
      <label>
        Description
        <textarea id="editor-description" rows="4" value={e.description} oninput={Msg.setDescription}></textarea>
      </label>
      <label>
        Column
        <select id="editor-column" value={e.column} onchange={Msg.setColumn}>
          {Html.forEach columns (·.id) fun c => <option value={c.id}>{c.name}</option>}
        </select>
      </label>
      <fieldset>
        <legend>Labels</legend>
        {Html.forEach Label.all (·.name) (viewLabelChoice e)}
      </fieldset>
      <footer>
        <button id="editor-delete" type="button" onclick={Msg.deleteCard}>Delete</button>
        <button id="editor-cancel" type="button" onclick={Msg.closeEditor}>Cancel</button>
        <button id="editor-save">Save</button>
      </footer>
    </form>
  </dialog>

/-- Returns the notice for `problem`. -/
def viewProblem (problem : String) : Html Msg :=
  <p id="problem" role="alert">
    {problem}
    <button onclick={Msg.dismissProblem}>Dismiss</button>
  </p>

/-- Returns the page for `m`. Leaving the columns while dragging clears the drop target. -/
def view (m : Model) : Html Msg :=
  <main ondragover={Msg.dragOver none}>
    {viewToolbar m}
    {m.problem.map viewProblem}
    <div id="board">
      {Html.forEach m.board.columns (·.id) (viewColumn m)}
      <button id="add-column" onclick={Msg.addColumn}>Add a column</button>
    </div>
    {m.editor.map (viewEditor m.board.columns)}
  </main>
