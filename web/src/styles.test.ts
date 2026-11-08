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
  it("keeps the corner text and the disconnect button away from the viewport edge", () => {
    expect(css).toMatch(/\.corner-brand, \.corner-title \{[^}]*left: var\(--side-inset\)/);
    expect(css).toMatch(/\.corner-action \{[^}]*right: var\(--side-inset\)/);
    expect(css).toMatch(/--side-inset: 36px/);
  });

  it("never shrinks the inset below 16px on small screens", () => {
    expect(css).toMatch(/@media \(max-width: 720px\) \{\s*:root \{ --edge-inset: 16px; --side-inset: 16px; \}/);
    expect(css).not.toMatch(/(right|left): 8px/);
  });

  it("pads the profile panel so its close button clears the edge", () => {
    expect(css).toMatch(/\.dossier \{[^}]*padding: 16px 18px/);
  });
});

describe("theme", () => {
  it("bundles Onest locally with a fallback stack and no remote font loading", () => {
    expect(css).toMatch(/@font-face \{ font-family: "Onest";[^}]*url\("\.\/fonts\/onest-latin-wght-normal\.woff2"\)/);
    expect(css).toMatch(/--font-sans: "Onest", [^;]*sans-serif;/);
    expect(css).not.toMatch(/fonts\.googleapis|fonts\.gstatic/);
  });

  it("follows kora_theme font variables with the original stacks as fallbacks", () => {
    expect(css).toMatch(/html, body, #root, button, input, select, textarea \{ font-family: var\(--font-sans\); \}/);
    expect(css).toMatch(/h1, h2, h3 \{ font-family: var\(--font-heading, var\(--font-sans\)\); \}/);
    expect(css).toMatch(/kbd \{[^}]*font: 500 12px var\(--font-mono, ui-monospace, monospace\);/);
    expect(css).toMatch(/\.json-editor textarea \{[^}]*font-family: var\(--font-mono, ui-monospace, SFMono-Regular, Consolas, monospace\);/);
    expect(css).toMatch(/\.cue-add input \{[^}]*font-family: var\(--font-mono, ui-monospace, monospace\);/);
    // Every font-family outside @font-face goes through a theme variable.
    const declarations = css.replace(/@font-face \{[^}]*\}/g, "").match(/font(-family)?:[^;]*;/g) ?? [];
    for (const declaration of declarations) expect(declaration).toMatch(/var\(--font-(sans|heading|mono)/);
  });

  it("drops the decorative accent rail, gradients and coloured glows", () => {
    expect(css).not.toMatch(/\.identity-card::before/);
    expect(css).not.toMatch(/gradient\(/);
    // A focus ring (0 0 0 Npx) is fine; a blurred glow (0 0 Npx) is not.
    expect(css).not.toMatch(/box-shadow: 0 0 [1-9]/);
  });

  it("centres icon buttons without inherited padding", () => {
    expect(css).toMatch(/\.icon-button, \.quiet-button \{[^}]*align-items: center; justify-content: center;[^}]*padding: 0; box-sizing: border-box/);
    expect(css).toMatch(/\.icon-button svg \{ display: block;/);
  });
});

describe("scene text legibility", () => {
  it("layers the scene text shadow so it has a tight dark edge plus a soft glow", () => {
    const shadow = css.match(/--scene-text-shadow: ([^;]*);/)?.[1] ?? "";
    expect(shadow.split(/,(?![^(]*\))/).length).toBeGreaterThanOrEqual(2);
  });

  it("draws overlay labels in the brighter scene colour, not plain muted grey", () => {
    for (const selector of [".corner-brand", ".third-kicker", ".third-meta", ".slot-rail li", ".key-hints", ".profile-count", ".new-slot-chip"]) {
      const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const rule = css.match(new RegExp(`${escaped} \\{([^}]*)\\}`))?.[1] ?? "";
      expect(rule, selector).toMatch(/color: var\(--scene-muted\)/);
      expect(rule, selector).not.toMatch(/color: hsl\(var\(--muted-foreground\)\)/);
    }
    expect(css).toMatch(/--scene-muted: hsl\(var\(--foreground\) \/ \.85\)/);
  });

  it("gives the profile counter its own text shadow, while the action row keeps none", () => {
    expect(css).toMatch(/\.profile-count \{[^}]*text-shadow: var\(--scene-text-shadow\)/);
    expect(css).toMatch(/\.third-actions \{[^}]*text-shadow: none/);
  });
});

describe("nav buttons", () => {
  it("dims disabled arrows through the icon colour, not opacity", () => {
    const rule = css.match(/\.nav-button:disabled \{([^}]*)\}/)?.[1] ?? "";
    expect(rule).not.toMatch(/opacity/);
    expect(rule).toMatch(/color: hsl\(var\(--muted-foreground\) \/ \.45\)/);
  });
});
