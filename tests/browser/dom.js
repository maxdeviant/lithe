// Runs programs from `tests/dom` in the browser that `BROWSER` names, as what's being checked depends
// on how a real HTML parser behaves. A program passes if it finishes without printing `FAIL`.

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { selectedBrowser } from "./harness.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const { label, launch } = selectedBrowser();

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.status !== 0) {
    console.error(result.stdout, result.stderr);
    process.exit(1);
  }
}

const browser = await launch();
let failed = false;
for (const name of ["Hydrate", "Json", "Random", "Render"]) {
  const dir = join(root, ".lake", "build", "tests", "browser", name);
  mkdirSync(dir, { recursive: true });
  const source = join(root, "tests", "dom", `${name}.lean`);
  run("lake", ["exe", "leanscript", "compile", source, "-o", join(dir, "main.mjs"), "--target", "browser"], root);
  writeFileSync(join(dir, "index.html"), `<!doctype html><script type="module" src="./main.mjs"></script>`);
  // The examples are what have Vite, which resolves the runtime from the root of the workspace.
  const dist = join(dir, "dist");
  run("pnpm", ["exec", "vite", "build", dir, "--outDir", dist, "--emptyOutDir"], join(root, "examples", "server"));

  const types = { ".html": "text/html", ".js": "text/javascript" };
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

  const page = await browser.newPage();
  const output = [];
  const finished = new Promise((resolve) => {
    page.on("console", (m) => {
      // Chrome and WebKit show the format string that the runtime's output goes through.
      const text = m.text().replace(/^%s /, "");
      output.push(text);
      if (text.startsWith("finished")) {
        resolve(true);
      }
    });
    page.on("pageerror", (e) => {
      output.push(`FAIL ${e.message}`);
      resolve(false);
    });
    setTimeout(() => resolve(false), 300_000).unref();
  });
  // These programs run for long enough to hold up the load event.
  await page.goto(`http://localhost:${server.address().port}/`, { waitUntil: "commit", timeout: 0 });
  const done = await finished;
  const failures = output.filter((line) => line.startsWith("FAIL"));
  const passed = done && failures.length === 0;
  console.log(`${passed ? "ok  " : "FAIL"} ${name} in ${label}`);
  if (!passed) {
    failed = true;
    console.log(failures.slice(0, 10).join("\n").slice(0, 4000));
  }
  await page.close();
  server.close();
}
await browser.close();
process.exit(failed ? 1 : 0);
