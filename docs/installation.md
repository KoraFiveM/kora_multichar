---
title: Installation
sidebar_position: 2
---

## Dependencies

`fxmanifest.lua` declares these dependencies:

- `kora_theme`
- `kora_lib`
- `kora_core`

`kora_clothing` is optional. When it is started, saved appearance is applied to the preview ped through `exports.kora_clothing:ApplyAppearanceToPed`, and new characters are dressed with `exports.kora_clothing:applyStarterAppearance()` (see `Config.newCharacter`). Without it previews show the default freemode model.

The resource also uses `qb-apartments` if it is started (see [Compatibility](./compatibility.md)).

## Start order

```cfg
ensure kora_sql
ensure kora_theme
ensure kora_lib
ensure kora_core
ensure kora_clothing
ensure kora_multichar
```

The resource `provide`s `qb-multicharacter` and `qb-spawn`, so do not run the stock versions at the same time.

## Database

No migration is needed.

## NUI build

The compiled React/Vite NUI is committed in `web/build` and is what `ui_page` serves. After changing `web/src`, rebuild with `npm install` then `npm run build` from the `web` directory.

## Optional: FFT hooks

`fft_hooks.lua` is inert unless the convar `fft_kora_hooks` is `true`. See [Events](./events.md#fft-hooks).
