// Builds the macro tests, checks where errors in holes are reported, runs the native program, then compiles each program in
// `tests/dom` for the browser and runs it in a page made with jsdom. A program passes if it finishes
// without printing `FAIL`.

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, readdirSync, statSync } from "node:fs";
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

// Returns the messages from compiling `file`.
function messagesOf(file) {
  const { stdout } = run("lake", ["env", "lean", "--json", file]);
  return stdout.trim().split("\n").map((line) => JSON.parse(line));
}

// Each error must point at the code in the hole, rather than at the whole element.
const errorsFile = join(root, "tests", "errors", "Holes.lean");
const expectedErrors = ["badAttr", "badChild", "42", "42", "nope"];
const lines = readFileSync(errorsFile, "utf8").split("\n");
const actualErrors = messagesOf(errorsFile).map(({ pos, endPos }) => {
  return pos.line === endPos.line
    ? lines[pos.line - 1].slice(pos.column, endPos.column)
    : `${pos.line}:${pos.column}-${endPos.line}:${endPos.column}`;
});
if (JSON.stringify(actualErrors) !== JSON.stringify(expectedErrors)) {
  console.log(`FAIL error positions\nexpected ${expectedErrors}\ngot ${actualErrors}`);
  process.exit(1);
}
console.log("ok   error positions");

// `#guard_msgs` can't check these, as parse errors happen outside of the command it wraps.
const parseErrors = messagesOf(join(root, "tests", "errors", "Parse.lean"))
  .filter((m) => m.severity === "error")
  .map((m) => `${m.pos.line}: ${m.data}`);
const afterExpr =
  "markup here is read as `<` comparing the line above with this tag, so end the line above with `;`";
const expectedParseErrors = [`11: ${afterExpr}`, `15: ${afterExpr}`, "19: unterminated HTML comment"];
if (JSON.stringify(parseErrors) !== JSON.stringify(expectedParseErrors)) {
  console.log(`FAIL parse errors\nexpected ${expectedParseErrors}\ngot ${parseErrors}`);
  process.exit(1);
}
console.log("ok   parse errors");

// This is the only check that links anything for native Lean, which is where a JS dependency would
// show up: `#eval` and building oleans both work without one being implemented.
const native = run("lake", ["exe", "lithe-native-test"]);
if (native.status !== 0) {
  console.log(`FAIL native\n${native.stdout}${native.stderr}`);
  process.exit(1);
}
// The compiler adds about 100 MB, and it only takes one import in the wrong place to link it in.
const nativeSize = statSync(join(root, ".lake", "build", "bin", "lithe-native-test")).size;
if (nativeSize > 20_000_000) {
  console.log(`FAIL native size\nthe native program is ${nativeSize} bytes`);
  process.exit(1);
}
console.log("ok   native");

// Returns the lines of a program's output that it prints for comparing targets.
function transcriptOf(stdout) {
  return stdout
    .split("\n")
    .filter((line) => line.startsWith("json "))
    .join("\n");
}

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
  // JSON that a native program writes has to mean the same to a client, and the other way around.
  if (name === "Json" && transcriptOf(result.stdout) !== transcriptOf(native.stdout)) {
    console.log(`FAIL JSON differs between native Lean and LeanScript`);
    failures++;
  }
  console.log(`${passed ? "ok  " : "FAIL"} ${name}${details}`);
  if (!passed) {
    failures++;
  }
}
process.exit(failures === 0 ? 0 : 1);
