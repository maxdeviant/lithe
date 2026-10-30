import Lithe
import Todo.Model

open Lithe

/-- Returns the list item for `todo`. -/
def viewTodo (todo : Todo) : Html Msg :=
  <li class={cls "done" todo.done}>
    <input class="toggle" type="checkbox" checked={todo.done} onchange={Msg.toggle todo.id} />
    <span>{todo.text}</span>
    <button class="remove" aria-label="Remove" onclick={Msg.remove todo.id}>×</button>
  </li>

/-- Returns the text that says how many items are left. -/
def countText (left : Nat) : String :=
  s!"{left} {if left == 1 then "item" else "items"} left"

/-- Returns the page for `m`. -/
def view (m : Model) : Html Msg :=
  <main>
    <h1>Todo</h1>
    <form onsubmit={preventDefault Msg.add}>
      <input
        id="new-todo-text"
        placeholder="What needs doing?"
        autocomplete="off"
        value={m.draft}
        oninput={Msg.setDraft}
        use={Action.focus}
      />
      <button>Add</button>
    </form>
    <ul id="todos">{Html.forEach m.todos (·.id) viewTodo}</ul>
    <footer>
      <span id="count">{countText m.itemsLeft}</span>
      <button
        id="clear-completed"
        hidden={m.todos.all (!·.done)}
        onclick={Msg.clearCompleted}
      >Clear completed</button>
    </footer>
  </main>
