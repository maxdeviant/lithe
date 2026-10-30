// Builds the todo example, and uses it in Chrome like a person would.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const example = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "examples", "todo");
const dist = join(example, "dist");

const build = spawnSync("pnpm", ["exec", "vite", "build"], { cwd: example, encoding: "utf8" });
if (build.status !== 0) {
  console.error(build.stdout, build.stderr);
  process.exit(1);
}

const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };
const server = createServer((req, res) => {
  const path = req.url === "/" ? "/index.html" : req.url;
  try {
    const body = readFileSync(join(dist, path));
    res.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((resolve) => server.listen(0, resolve));

const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => {
  if (m.type() === "error") {
    errors.push(m.text());
  }
});

try {
  await page.goto(`http://localhost:${server.address().port}/`);

  const input = page.locator("#new-todo-text");
  await input.waitFor();
  assert.equal(await page.evaluate(() => document.activeElement?.id), "new-todo-text");

  const items = () => page.locator("#todos li span").allTextContents();
  const count = () => page.locator("#count").textContent();

  await input.pressSequentially("  buy milk ");
  await input.press("Enter");
  assert.deepEqual(await items(), ["buy milk"]);
  assert.equal(await input.inputValue(), "", "adding an item clears the input");
  assert.equal(await count(), "1 item left");

  await input.pressSequentially("walk dog");
  await page.locator("form button").click();
  await input.fill("call home");
  await input.press("Enter");
  assert.deepEqual(await items(), ["buy milk", "walk dog", "call home"]);
  assert.equal(await count(), "3 items left");

  await input.pressSequentially("   ");
  await input.press("Enter");
  assert.equal((await items()).length, 3, "blank items are ignored");
  await input.fill("");

  // Typing in the middle of the text must not move the cursor, as the input is controlled.
  await input.pressSequentially("ac");
  await input.press("ArrowLeft");
  await input.pressSequentially("b");
  assert.equal(await input.inputValue(), "abc");
  await input.fill("");

  const clear = page.locator("#clear-completed");
  assert.equal(await clear.isVisible(), false);

  await page.locator("#todos li", { hasText: "walk dog" }).locator(".toggle").check();
  assert.equal(await count(), "2 items left");
  assert.equal(await page.locator("#todos li.done span").textContent(), "walk dog");
  assert.equal(await clear.isVisible(), true);

  await page.locator("#todos li", { hasText: "buy milk" }).locator(".remove").click();
  assert.deepEqual(await items(), ["walk dog", "call home"]);

  await clear.click();
  assert.deepEqual(await items(), ["call home"]);
  assert.equal(await count(), "1 item left");
  assert.equal(await clear.isVisible(), false);

  assert.deepEqual(errors, [], "the page reported no errors");
  console.log("ok   todo example in Chrome");
} finally {
  await browser.close();
  server.close();
}
