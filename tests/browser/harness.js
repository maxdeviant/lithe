// Builds an example, serves it, and opens it in Chrome.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

export async function withExample(name, use) {
  const example = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "examples", name);
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
    await use(page);
    assert.deepEqual(errors, [], "the page reported no errors");
    console.log(`ok   ${name} example in Chrome`);
  } finally {
    await browser.close();
    server.close();
  }
}
