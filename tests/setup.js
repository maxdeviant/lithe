// Makes the globals that compiled programs use those of a page made with jsdom.

import { JSDOM } from "jsdom";

const { window } = new JSDOM(`<!doctype html><body></body>`);
for (const name of [
  "document",
  "DOMTokenList",
  "Document",
  "Element",
  "Event",
  "EventTarget",
  "HTMLElement",
  "HTMLInputElement",
  "KeyboardEvent",
  "MutationObserver",
  "Node",
  "Text",
]) {
  globalThis[name] = window[name];
}
