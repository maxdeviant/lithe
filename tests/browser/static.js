// Uses the static example, whose pages are files from a native program, with and without JS.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { selectedBrowser } from "./harness.js";

const example = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "examples", "static");
const dist = join(example, "dist");

const build = spawnSync("pnpm", ["build"], { cwd: example, encoding: "utf8" });
if (build.status !== 0) {
  console.error(build.stdout, build.stderr);
  process.exit(1);
}

const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };
const server = createServer((req, res) => {
  const path = req.url.endsWith("/") ? `${req.url}index.html` : req.url;
  try {
    const body = readFileSync(join(dist, path));
    res.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${server.address().port}`;

// Fails if a page is replaced, which logs an error, or if anything else goes wrong.
function collectErrors(page) {
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => {
    if (m.type() === "error") {
      errors.push(m.text());
    }
  });
  return errors;
}

const { label, launch } = selectedBrowser();
const browser = await launch();
try {
  // What the generator wrote, before anything has run in a browser.
  const html = readFileSync(join(dist, "glossary", "index.html"), "utf8");
  assert.match(html, /^<!doctype html><html lang="en">/);
  assert.match(html, /<title>Glossary &amp; terms<\/title>/);
  assert.match(html, /<dt>Hydration<\/dt>/);
  assert.match(html, /a server &lt;or a build&gt;/);
  assert.match(html, /<script id="terms" type="application\/json">\[\{"name":"Hydration"/);
  assert.match(html, /a server \\u003cor a build>/);
  assert.doesNotMatch(readFileSync(join(dist, "index.html"), "utf8"), /id="terms"/);

  // Without JS, the content is all there, and the controls that need JS are hidden.
  const noJs = await browser.newContext({ javaScriptEnabled: false });
  const staticPage = await noJs.newPage();
  await staticPage.goto(`${url}/glossary/`);
  assert.equal(await staticPage.locator("dt").count(), 4);
  assert.equal(await staticPage.locator("#filter").isVisible(), false);
  assert.equal(await staticPage.locator("#theme-switcher").isVisible(), false);
  await noJs.close();

  const context = await browser.newContext({ colorScheme: "light" });
  const page = await context.newPage();
  const errors = collectErrors(page);
  // Holds the client back, to mark what's on the page before it runs.
  let release;
  const gate = new Promise((resolve) => (release = resolve));
  await page.route("**/assets/*.js", async (route) => {
    await gate;
    await route.continue();
  });
  await page.goto(`${url}/glossary/`, { waitUntil: "commit" });
  await page.waitForSelector("#terms", { state: "attached" });
  await page.evaluate(() => {
    window.kept = [...document.querySelectorAll("#theme *, #glossary *")];
  });
  release();

  // The islands start separately, and each adopts the page rather than replacing it.
  const switcher = page.locator("#theme-switcher");
  const filter = page.locator("#filter");
  await switcher.waitFor({ state: "visible" });
  await filter.waitFor({ state: "visible" });
  assert.equal(await switcher.textContent(), "Use the dark theme", "the browser knows the theme");
  assert.equal(
    await page.evaluate(() => {
      const now = [...document.querySelectorAll("#theme *, #glossary *")];
      return now.length === window.kept.length && now.every((e, i) => e === window.kept[i]);
    }),
    true,
    "the client keeps every element from the page",
  );

  // The islands respond separately, on the same page.
  await filter.fill("hYdR");
  await page.waitForFunction(() => document.querySelectorAll("dt").length === 1);
  assert.equal(await page.locator("dt").textContent(), "Hydration");
  assert.equal(await page.locator("#filter-count").textContent(), "1 of 4 terms");
  assert.equal(await page.locator("dd").textContent(), "Making a page from a server <or a build> interactive without replacing it.");
  await switcher.click();
  await page.waitForFunction(() => document.documentElement.dataset.theme === "dark");
  assert.equal(await switcher.textContent(), "Use the light theme");
  assert.equal(await filter.inputValue(), "hYdR", "the other island keeps its state");
  assert.equal(await page.locator("dt").count(), 1);
  await filter.fill("");
  await page.waitForFunction(() => document.querySelectorAll("dt").length === 4);
  assert.equal(await page.locator("#filter-count").textContent(), "4 of 4 terms");

  // Another page has only the switcher, and starts with the saved theme.
  await page.locator('a[href="/"]').click();
  await page.waitForFunction(() => document.querySelector("h1")?.textContent === "A static site");
  await page.waitForFunction(() => document.querySelector("#theme-switcher")?.textContent === "Use the light theme");
  assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), "dark");
  assert.equal(await page.evaluate(() => localStorage.getItem("theme")), "dark");
  assert.equal(await page.locator("#filter").count(), 0);

  // Choosing the system's theme clears what's saved.
  await page.locator("#theme-switcher").click();
  await page.waitForFunction(() => document.documentElement.dataset.theme === undefined);
  assert.equal(await page.evaluate(() => localStorage.getItem("theme")), null);
  assert.equal(await page.locator("#theme-switcher").textContent(), "Use the dark theme");

  assert.deepEqual(errors, [], "the page reported no errors");
  console.log(`ok   static example in ${label}`);
} finally {
  await browser.close();
  server.close();
}
