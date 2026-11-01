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

describe("edge insets", () => {
  it("keeps the top bar icon buttons away from the viewport edge", () => {
    expect(css).toMatch(/\.topbar \{[^}]*left: var\(--topbar-inset\); right: var\(--topbar-inset\)/);
    expect(css).toMatch(/--topbar-inset: calc\(var\(--edge-inset\) \+ 28px\)/);
  });

  it("never shrinks the inset below 16px on small screens", () => {
    expect(css).toMatch(/@media \(max-width: 720px\) \{\s*:root \{ --edge-inset: 16px; --topbar-inset: var\(--edge-inset\); \}/);
    expect(css).not.toMatch(/(right|left): 8px/);
  });

  it("pads panel close buttons from the panel edge", () => {
    expect(css).toMatch(/\.dossier-heading, \.panel-heading \{ padding-right: 4px; \}/);
  });
});

describe("theme", () => {
  it("bundles Onest locally with a fallback stack and no remote font loading", () => {
    expect(css).toMatch(/@font-face \{ font-family: "Onest";[^}]*url\("\.\/fonts\/onest-latin-wght-normal\.woff2"\)/);
    expect(css).toMatch(/--font-sans: "Onest", [^;]*sans-serif;/);
    expect(css).not.toMatch(/fonts\.googleapis|fonts\.gstatic/);
  });

  it("drops the decorative accent rail, gradients and coloured glows", () => {
    expect(css).not.toMatch(/\.identity-card::before/);
    expect(css).not.toMatch(/gradient\(/);
    expect(css).not.toMatch(/box-shadow: 0 0 \d/);
  });

  it("centres icon buttons without inherited padding", () => {
    expect(css).toMatch(/\.icon-button \{[^}]*place-items: center;[^}]*padding: 0; box-sizing: border-box/);
    expect(css).toMatch(/\.icon-button svg \{ display: block;/);
  });
});
