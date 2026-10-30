// Builds the macro tests, then compiles each program in `tests/dom` for the browser and runs it in
// a page made with jsdom. A program passes if it finishes without printing `FAIL`.

import { spawnSync } from "node:child_process";
import { mkdirSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const programs = join(root, "tests", "dom");
const outDir = join(root, ".lake", "build", "tests");
mkdirSync(outDir, { recursive: true });

function run(command, args) {
  return spawnSync(command, args, { cwd: root, encoding: "utf8", timeout: 300_000 });
}

const build = run("lake", ["build", "Lithe", "LitheTest"]);
if (build.status !== 0) {
  console.log(`FAIL macro tests\n${build.stdout}${build.stderr}`);
  process.exit(1);
}
console.log("ok   macro tests");

const only = process.argv[2];
let failures = 0;
for (const file of readdirSync(programs).sort()) {
  const name = file.replace(/\.lean$/, "");
  if (!file.endsWith(".lean") || (only !== undefined && name !== only)) {
    continue;
  }
  const output = join(outDir, `${name}.mjs`);
  const compile = run("lake", [
    "exe",
    "leanscript",
    "compile",
    join(programs, file),
    "-o",
    output,
    "--target",
    "browser",
  ]);
  if (compile.status !== 0) {
    console.log(`FAIL ${name} (compile)\n${compile.stdout}${compile.stderr}`);
    failures++;
    continue;
  }
  const result = run(process.execPath, [
    "--conditions=browser",
    `--import=${join(root, "tests", "setup.js")}`,
    output,
  ]);
  const passed =
    result.status === 0 && !result.stdout.includes("FAIL") && result.stdout.includes("finished");
  const details = process.env.VERBOSE || !passed ? `\n${result.stdout}${result.stderr}` : "";
  console.log(`${passed ? "ok  " : "FAIL"} ${name}${details}`);
  if (!passed) {
    failures++;
  }
}
process.exit(failures === 0 ? 0 : 1);
