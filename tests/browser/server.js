// Uses the server example, whose page comes from a native program, with and without JS.

import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { selectedBrowser } from "./harness.js";

const example = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "examples", "server");

for (const [command, args] of [
  ["pnpm", ["exec", "vite", "build"]],
  ["lake", ["build", "server"]],
]) {
  const build = spawnSync(command, args, { cwd: example, encoding: "utf8" });
  if (build.status !== 0) {
    console.error(build.stdout, build.stderr);
    process.exit(1);
  }
}

const server = spawn(join(example, ".lake", "build", "bin", "server"), ["0", join(example, "dist")], {
  stdio: ["ignore", "pipe", "inherit"],
});

const { label, launch } = selectedBrowser();
let browser;
try {
  const url = await new Promise((resolve, reject) => {
    server.once("exit", (code) => reject(new Error(`the server exited with ${code}`)));
    createInterface({ input: server.stdout }).once("line", (line) => {
      resolve(line.replace("listening on ", ""));
    });
  });

  // What the native program sends, before anything has run in a browser.
  const response = await fetch(url);
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /^text\/html/);
  const html = await response.text();
  assert.match(html, /<output id="count">3<\/output>/);
  assert.match(html, /<rect id="bar" height="1" width="3"><\/rect>/);
  assert.doesNotMatch(html, /<div id="app"><\/div>/);
  assert.doesNotMatch(html, /onclick/, "handlers have no form in HTML");

  const [, script] = html.match(/src="\/(assets\/[^"]+\.js)"/);
  const asset = await fetch(url + script);
  assert.equal(asset.status, 200);
  assert.match(asset.headers.get("content-type"), /^text\/javascript/);
  assert.equal((await fetch(`${url}missing.js`)).status, 404);
  assert.equal((await fetch(`${url}assets`)).status, 404, "directories aren't files");
  assert.equal((await fetch(`${url}..%2flakefile.toml`)).status, 404, "nothing outside of the build");

  browser = await launch();

  // Without JS, the page is all there.
  const noJs = await browser.newContext({ javaScriptEnabled: false });
  const staticPage = await noJs.newPage();
  await staticPage.goto(url);
  assert.equal(await staticPage.locator("#count").textContent(), "3");
  assert.equal(await staticPage.locator("#increment").count(), 1);
  assert.equal(await staticPage.locator("#bar").getAttribute("width"), "3");
  await noJs.close();

  // With JS, the client takes over the same page.
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => {
    if (m.type() === "error") {
      errors.push(m.text());
    }
  });
  await page.goto(url);
  await page.waitForFunction(() => document.activeElement?.id === "increment");
  assert.equal(await page.locator("main").count(), 1, "the client replaces the server's page");
  await page.locator("#increment").click();
  await page.locator("#increment").click();
  await page.locator("#decrement").click();
  await page.waitForFunction(() => document.querySelector("#count").textContent === "4");
  assert.equal(await page.locator("#bar").getAttribute("width"), "4");
  assert.deepEqual(errors, [], "the page reported no errors");
  console.log(`ok   server example in ${label}`);
} finally {
  await browser?.close();
  server.removeAllListeners("exit");
  server.kill();
}
