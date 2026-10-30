// Uses the kanban example in a browser, as someone who drags cards, edits them, and comes back later.

import assert from "node:assert/strict";
import { withExample } from "./harness.js";

await withExample("kanban", async (page) => {
  const columnAt = (i) => page.locator(".column").nth(i);
  const titles = (i) => columnAt(i).locator(".card a").allTextContents();
  const card = (title) => page.locator(".card").filter({ hasText: title });
  const dialog = page.locator("dialog#editor");
  const save = page.locator("#editor-save");
  const undo = page.locator("#undo");
  const redo = page.locator("#redo");

  await page.locator(".column").first().waitFor();
  assert.equal(await page.locator(".column").count(), 3);
  assert.deepEqual(await titles(0), ["Write the release notes", "Fix the flaky upload test"]);
  assert.ok(await undo.isDisabled(), "there's nothing to undo at first");

  // Adding cards. The input keeps the focus however the card is added.
  await columnAt(0).locator(".add-card").click();
  const newCard = columnAt(0).locator(".new-card input");
  assert.ok(await newCard.evaluate((el) => el === document.activeElement), "the form takes focus");
  await newCard.fill("First");
  await page.keyboard.press("Enter");
  await columnAt(0).locator(".new-card button", { hasText: "Add" }).waitFor();
  await newCard.fill("Second");
  await columnAt(0).locator(".new-card button", { hasText: "Add" }).click();
  assert.equal(await newCard.inputValue(), "");
  assert.ok(await newCard.evaluate((el) => el === document.activeElement), "the input is focused again");
  await page.keyboard.press("Escape");
  assert.equal(await columnAt(0).locator(".new-card").count(), 0, "Escape closes the form");
  assert.deepEqual((await titles(0)).slice(-2), ["First", "Second"]);

  // Moving a card with its buttons.
  assert.ok(await card("First").getByLabel("Move left").isDisabled());
  await card("First").getByLabel("Move right").click();
  assert.deepEqual(await titles(1), ["Add dark mode", "First"]);

  // Dragging a card onto another, and into the empty part of a column.
  const draggedNode = await card("Second").elementHandle();
  await card("Second").dragTo(card("Write the release notes"), { targetPosition: { x: 20, y: 5 } });
  assert.deepEqual(await titles(0), ["Second", "Write the release notes", "Fix the flaky upload test"]);
  assert.ok(
    await draggedNode.evaluate((el) => el.isConnected),
    "reordering within a column keeps the card's DOM node",
  );
  assert.equal(await page.locator(".dragging, .drop-before, .drop-end").count(), 0, "dropping clears the markers");

  await card("Second").dragTo(columnAt(2).locator("header"));
  assert.deepEqual(await titles(2), ["Set up CI", "Second"]);

  await card("Set up CI").dragTo(card("Set up CI"));
  assert.deepEqual(await titles(2), ["Set up CI", "Second"], "dropping a card on itself does nothing");

  // Undo and redo, with the buttons and the keyboard.
  await undo.click();
  assert.deepEqual(await titles(0), ["Second", "Write the release notes", "Fix the flaky upload test"]);
  await redo.click();
  assert.deepEqual(await titles(2), ["Set up CI", "Second"]);
  await page.keyboard.press("ControlOrMeta+z");
  assert.equal((await titles(0))[0], "Second");
  await page.keyboard.press("ControlOrMeta+Shift+z");
  assert.deepEqual(await titles(2), ["Set up CI", "Second"]);

  // A text field's undo belongs to the text field.
  await page.locator("#search").focus();
  await page.keyboard.press("ControlOrMeta+z");
  assert.deepEqual(await titles(2), ["Set up CI", "Second"]);

  // Searching and filtering.
  await page.locator("#search").fill("DARK");
  assert.deepEqual(await titles(1), ["Add dark mode"]);
  assert.equal(await columnAt(1).locator(".count").textContent(), "1 of 2");
  assert.equal(await columnAt(0).locator(".card").count(), 0);
  await page.locator("#search").fill("");
  await page.locator(".filters button", { hasText: "bug" }).click();
  assert.deepEqual(await titles(0), ["Fix the flaky upload test"]);
  await page.locator(".filters button", { hasText: "bug" }).click();
  assert.equal(await columnAt(1).locator(".count").textContent(), "2");

  // Opening a card is a link, so the URL says so and the back button closes it.
  await card("Add dark mode").locator("a").click();
  await dialog.waitFor();
  assert.match(page.url(), /#\/card\/\d+$/);
  assert.ok(await dialog.evaluate((el) => el.matches(":modal")), "it's a real modal");
  const title = page.locator("#editor-title");
  assert.equal(await title.inputValue(), "Add dark mode");
  assert.equal(await page.locator("#editor-description").inputValue(), "Follow the system setting.");
  assert.equal(await page.locator("#editor-column option:checked").textContent(), "Doing");
  assert.ok(await title.evaluate((el) => el === document.activeElement), "the title takes focus");
  await page.goBack();
  await dialog.waitFor({ state: "detached" });

  // Escape discards the draft, using only the browser's own behavior for dialogs.
  // Safari doesn't focus a link on click, so this uses the keyboard to know where focus should return.
  await card("Add dark mode").locator("a").focus();
  await page.keyboard.press("Enter");
  await title.fill("Discarded");
  await page.keyboard.press("Escape");
  await dialog.waitFor({ state: "detached" });
  assert.equal(page.url().endsWith("#/"), true);
  assert.equal(await card("Discarded").count(), 0);
  assert.ok(
    await card("Add dark mode").locator("a").evaluate((el) => el === document.activeElement),
    "focus goes back to the link",
  );

  // Saving a card, including moving it through the select.
  await card("Add dark mode").locator("a").click();
  await title.fill("Add a dark mode");
  await page.locator("#editor-description").fill("Follow\nthe system.");
  await dialog.getByLabel("bug").check();
  await page.locator("#editor-column").selectOption({ label: "Done" });
  await save.click();
  await dialog.waitFor({ state: "detached" });
  assert.deepEqual(await titles(2), ["Set up CI", "Second", "Add a dark mode"]);
  assert.deepEqual(await card("Add a dark mode").locator(".labels li").allTextContents(), ["feature", "bug"]);
  assert.equal(page.url().endsWith("#/"), true);

  // A title is required.
  await card("First").locator("a").click();
  await title.fill("   ");
  await save.click();
  assert.equal(await dialog.count(), 1, "a blank title doesn't save");
  await page.locator("#editor-cancel").click();
  await dialog.waitFor({ state: "detached" });

  // Deleting a card, and getting it back.
  await card("First").locator("a").click();
  await page.locator("#editor-delete").click();
  await dialog.waitFor({ state: "detached" });
  assert.equal(await card("First").count(), 0);
  await undo.click();
  assert.equal(await card("First").count(), 1);

  // Columns are a keyed list too, so a card's column keeps its nodes when it moves.
  await page.locator("#add-column").click();
  const last = columnAt(3);
  const name = last.locator(".column-name");
  assert.equal(await name.inputValue(), "New column");
  await name.fill("Later");
  await name.press("Tab");
  const lastNode = await last.elementHandle();
  await last.getByLabel("Move column left").click();
  assert.equal(await columnAt(2).locator(".column-name").inputValue(), "Later");
  assert.ok(await lastNode.evaluate((el) => el.isConnected), "moving a column keeps its DOM node");
  assert.ok(await columnAt(0).getByLabel("Remove column").isDisabled(), "a column with cards stays");
  await columnAt(2).getByLabel("Remove column").click();
  assert.equal(await page.locator(".column").count(), 3);

  // The board survives a reload, and so does an open card.
  await card("First").locator("a").click();
  await dialog.waitFor();
  await page.reload();
  await dialog.waitFor();
  assert.equal(await title.inputValue(), "First");
  assert.deepEqual(await titles(2), ["Set up CI", "Second", "Add a dark mode"]);
  await page.locator("#editor-cancel").click();
  await dialog.waitFor({ state: "detached" });

  // A link to a card that doesn't exist goes to the board.
  await page.evaluate(() => {
    location.hash = "#/card/9999";
  });
  await page.waitForFunction(() => location.hash === "#/");
  assert.equal(await dialog.count(), 0);

  // Failing to save is reported rather than lost.
  await page.evaluate(() => {
    Storage.prototype.setItem = () => {
      throw new Error("quota");
    };
  });
  await columnAt(0).getByLabel("Move column right").click();
  const problem = page.locator("#problem");
  await problem.waitFor();
  assert.match(await problem.textContent(), /Couldn't save the board/);
  await problem.locator("button").click();
  await problem.waitFor({ state: "detached" });

  // A saved board that can't be read is reported, and the app still starts.
  await page.reload();
  await page.locator(".column").first().waitFor();
  await page.evaluate(() => localStorage.setItem("lithe-kanban-board", '{"columns": 3}'));
  await page.reload();
  await problem.waitFor();
  assert.match(await problem.textContent(), /Couldn't read the saved board/);
  assert.equal(await page.locator(".column").count(), 3);

  await page.evaluate(() =>
    localStorage.setItem(
      "lithe-kanban-board",
      JSON.stringify({ columns: [], cards: [{ id: 1, column: 7, title: "x", description: "", labels: [] }], nextId: 9 }),
    ),
  );
  await page.reload();
  await problem.waitFor();
  assert.match(await problem.textContent(), /don't match up/);
});
