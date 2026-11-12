---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Multichar is the cinematic character-select, character-creation and spawn screen. It replaces both the stock qb-multicharacter UI and qb-spawn in one resource, and depends on kora_theme, kora_lib and kora_core.

## Install Kora Multichar

1. **Add the folder** — Place `kora_multichar` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_multichar`).

2. **Check the build is present** — The UI is a built React app served from `web/build/index.html`. A fresh clone should already carry `web/build/` — if it is missing, see "The NUI is a build artifact" below before starting the resource; without it the resource has nothing to show.

3. **Start it after its dependencies** — It needs kora_theme (used by `@kora_theme/client/bridge.lua`), kora_lib (`@kora_lib/init.lua`, for `Kora.callback`, `Kora.config`, `Kora.freecam`, `Kora.permissions`, etc.) and kora_core (character ownership) to already be running.

   ```bash title="server.cfg"
   ensure kora_theme
   ensure kora_lib
   ensure kora_core
   ensure kora_multichar
   ```

4. **Nothing else to `ensure`** — Do not also start a real qb-multicharacter or qb-spawn resource: this resource `provide`s both names (see Compatibility below) and fully replaces them.

   ```lua title="fxmanifest.lua" {5,6}
   dependency 'kora_theme'
   dependency 'kora_lib'
   dependency 'kora_core'

   provide 'qb-multicharacter'
   provide 'qb-spawn'
   ```

## The NUI is a build artifact

The character-select, creation and spawn screens are a React app in `web/src`, compiled by Vite into `web/build/`, which is what the manifest actually ships (`ui_page 'web/build/index.html'`, plus `web/build/**/*` in `files`). Editing `web/src` has no effect in-game until it is rebuilt.

1. **Install dependencies once** — From the `web/` folder:

   ```text title="shell"
   cd web
   npm install
   ```

2. **Rebuild after any web/src change** — Also run from `web/` — this is the actual script name in `web/package.json`, not an assumed `npm run build`:

   ```text title="shell"
   npm run build
   ```

3. **Restart the resource** — Run `sudo /opt/claude-bugfix/apply-fix.sh --restart kora_multichar` (or your own restart path) so the game client reloads `web/build/index.html`.

> **Note:** `npm run build` runs `tsc --noEmit && vite build` (type-checks, then builds). `npm run typecheck` and `npm run test` (vitest) are also available for working on the NUI without a full build.

## Dependencies and start order (from the manifest)

`fxmanifest.lua` declares `kora_theme`, `kora_lib` and `kora_core` as dependencies. `kora_clothing` is optional: when it is started, saved appearance is applied to the preview ped through `exports.kora_clothing:ApplyAppearanceToPed`, and new characters are dressed with `exports.kora_clothing:applyStarterAppearance()` (see `Config.newCharacter`). Without it previews show the default freemode model. The resource also uses `qb-apartments` if it is started (see [Compatibility](./compatibility.md)).

A full Kora start order:

```cfg title="server.cfg"
ensure kora_sql
ensure kora_theme
ensure kora_lib
ensure kora_core
ensure kora_clothing
ensure kora_multichar
```

## Database

No migration is needed. This resource has no SQL and no tables of its own; characters are read and written by `kora_core`.

## Optional: FFT hooks

`fft_hooks.lua` is inert unless the convar `fft_kora_hooks` is `true`. See [Events](./events.md#fft-hooks).
