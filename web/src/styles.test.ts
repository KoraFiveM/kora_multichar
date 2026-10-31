import { describe, expect, it } from 'vitest';
// The web project does not ship @types/node, so the Node built-ins used to read
// the stylesheet are loaded untyped.
// @ts-ignore
import { readFileSync } from "node:fs";
// @ts-ignore
import { fileURLToPath } from "node:url";

const css: string = readFileSync(fileURLToPath(new URL("./styles.css", import.meta.url)), "utf8");

describe('text selection', () => {
  it('disables selection on UI text but keeps editable fields selectable', () => {
    expect(css).toMatch(/#root \* \{ -webkit-user-select: none; user-select: none; \}/);
    expect(css).toMatch(/#root input, #root textarea, #root \[contenteditable=""\][^{]*\{ -webkit-user-select: text; user-select: text; \}/);
    // Same-or-higher specificity as the blanket rule, otherwise it would not win.
    expect(css.indexOf('#root input')).toBeGreaterThan(css.indexOf('#root * {'));
  });

  it('stops images and icons from being dragged', () => {
    expect(css).toMatch(/img, svg \{ -webkit-user-drag: none/);
  });
});
