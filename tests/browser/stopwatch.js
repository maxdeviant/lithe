// Uses the stopwatch example in Chrome, with the mouse and with the keyboard.

import assert from "node:assert/strict";
import { withExample } from "./harness.js";

await withExample("stopwatch", async (page) => {
  const time = page.locator("#time");
  const toggle = page.locator("#toggle");
  const laps = page.locator("#laps li");

  await time.waitFor();
  assert.equal(await time.textContent(), "00:00.0");

  await toggle.click();
  assert.equal(await toggle.textContent(), "Stop");
  await page.waitForFunction(() => document.querySelector("#time").textContent !== "00:00.0");

  await page.keyboard.press("l");
  assert.equal(await laps.count(), 1, "the keyboard shortcut for a lap works");
  await page.keyboard.press("x");
  assert.equal(await laps.count(), 1, "other keys do nothing");

  await page.keyboard.press("s");
  assert.equal(await toggle.textContent(), "Start");
  const stopped = await time.textContent();
  await page.waitForTimeout(300);
  assert.equal(await time.textContent(), stopped, "the timer stops ticking");

  await page.keyboard.press("s");
  await page.waitForFunction((t) => document.querySelector("#time").textContent !== t, stopped);
  const resumed = await time.textContent();
  assert.ok(resumed < "00:01.0", `the time stopped doesn't count, got ${resumed}`);

  await page.locator("#reset").click();
  assert.equal(await time.textContent(), "00:00.0");
  assert.equal(await laps.count(), 0);
});
