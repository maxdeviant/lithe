// Builds the benchmark app, then runs each operation in Chrome, reporting how long each takes and
// where a CPU profile says the time goes. Pass `--profile` to include the profiles.

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const dir = dirname(fileURLToPath(import.meta.url));
const dist = join(dir, "dist");
const samples = 21;
// Runs before the samples that are thrown away, for the JIT to warm up.
const warmup = 5;

const build = spawnSync("pnpm", ["exec", "vite", "build"], { cwd: dir, encoding: "utf8" });
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
const url = `http://localhost:${server.address().port}/`;

const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => {
  if (m.type() === "error") {
    errors.push(m.text());
  }
});

/**
 * Clicks what `selector` matches, and returns the milliseconds until the update has been made, and
 * until it has also been laid out, which is the browser's own work.
 */
const timedClick = (selector) =>
  page.evaluate(async (selector) => {
    const target = document.querySelector(selector);
    const start = performance.now();
    target.click();
    // Rendering is scheduled as a microtask, and this one runs after it.
    await new Promise((resolve) => queueMicrotask(resolve));
    const script = performance.now() - start;
    document.body.offsetHeight;
    return { script, total: performance.now() - start };
  }, selector);

const click = (selector) => timedClick(selector);

const rowCount = () => page.evaluate(() => document.querySelectorAll("tbody tr").length);

const operations = [
  { name: "create 1,000 rows", before: ["#clear"], run: "#create", rows: 1000 },
  { name: "replace 1,000 rows", before: ["#create"], run: "#create", rows: 1000 },
  { name: "update every 10th row of 1,000", before: ["#create"], run: "#update", rows: 1000 },
  { name: "select a row of 1,000", before: ["#create"], run: "tbody tr:nth-child(2) a.lbl", rows: 1000 },
  { name: "swap 2 rows of 1,000", before: ["#create"], run: "#swap", rows: 1000 },
  { name: "remove a row of 1,000", before: ["#create"], run: "tbody tr:nth-child(5) a.remove", rows: 999 },
  { name: "append 1,000 rows to 1,000", before: ["#clear", "#create"], run: "#append", rows: 2000 },
  { name: "clear 1,000 rows", before: ["#create"], run: "#clear", rows: 0 },
  { name: "create 10,000 rows", before: ["#clear"], run: "#createLots", rows: 10000 },
  { name: "update every 10th row of 10,000", before: ["#createLots"], run: "#update", rows: 10000 },
];

const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];

/**
 * Returns the milliseconds of a CPU profile's self time in each category of JS work. `(program)`
 * is left out, as it includes the idle time around the operation.
 */
function summarize(profile) {
  const byId = new Map(profile.nodes.map((n) => [n.id, n]));
  const categories = { lean: 0, runtime: 0, dom: 0, gc: 0 };
  const functions = new Map();
  profile.samples.forEach((id, i) => {
    const { functionName, url } = byId.get(id).callFrame;
    const time = (profile.timeDeltas[i] ?? 0) / 1000;
    if (functionName === "(idle)" || functionName === "(program)" || functionName === "(root)") {
      return;
    }
    if (functionName === "(garbage collector)") {
      categories.gc += time;
    } else if (url === "") {
      categories.dom += time;
    } else if (functionName.startsWith("l_")) {
      categories.lean += time;
    } else {
      categories.runtime += time;
    }
    functions.set(functionName, (functions.get(functionName) ?? 0) + time);
  });
  const top = [...functions.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(([n, t]) => `${n || "(anonymous)"} ${t.toFixed(1)}`);
  return { categories, top };
}

const showProfile = process.argv.includes("--profile");
const cdp = await page.context().newCDPSession(page);
await cdp.send("Profiler.enable");
await cdp.send("Profiler.setSamplingInterval", { interval: 200 });

console.log("| Operation | Script (ms) | With layout (ms) | Slowest with layout (ms) |");
console.log("|---|---:|---:|---:|");
const profiles = [];
for (const op of operations) {
  const scripts = [];
  const totals = [];
  const iterations = op.rows >= 2000 || op.name.includes("10,000") ? 11 : samples;
  for (let i = 0; i < warmup + iterations; i++) {
    await page.goto(url);
    await page.waitForSelector("#create");
    // Repeating the setup warms up the JIT on this page, which is reloaded for every sample.
    for (let j = 0; j < warmup; j++) {
      for (const step of op.before) {
        await click(step);
      }
    }
    const profiling = i === warmup;
    if (profiling) {
      await cdp.send("Profiler.start");
    }
    const { script, total } = await timedClick(op.run);
    if (profiling) {
      const { profile } = await cdp.send("Profiler.stop");
      profiles.push([op.name, summarize(profile)]);
    }
    const rows = await rowCount();
    if (rows !== op.rows) {
      throw new Error(`${op.name}: expected ${op.rows} rows, got ${rows}`);
    }
    if (i >= warmup) {
      scripts.push(script);
      totals.push(total);
    }
  }
  console.log(
    `| ${op.name} | ${median(scripts).toFixed(1)} | ${median(totals).toFixed(1)} | ${Math.max(...totals).toFixed(1)} |`,
  );
}
if (showProfile) {
  console.log("\nSelf time in one profiled run (ms):\n");
  console.log("| Operation | Lean | Runtime | DOM | GC | Top functions |");
  console.log("|---|---:|---:|---:|---:|---|");
  for (const [name, { categories: c, top }] of profiles) {
    console.log(
      `| ${name} | ${c.lean.toFixed(1)} | ${c.runtime.toFixed(1)} | ${c.dom.toFixed(1)} | ${c.gc.toFixed(1)} | ${top.join(", ")} |`,
    );
  }
}
if (errors.length > 0) {
  console.error(`\nPage errors:\n${errors.join("\n")}`);
}
await browser.close();
server.close();
