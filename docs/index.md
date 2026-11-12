---
title: kora_multichar
sidebar_position: 1
---

`kora_multichar` is the cinematic character selection, spawn selection and scene studio resource for `kora_core`. It replaces both legacy UIs (`qb-multicharacter` and `qb-spawn`) and keeps their event and callback protocols. See `version` in `fxmanifest.lua` for the release version.

Selecting a character only previews their saved appearance in a scene. The character is not logged in until **Continue** (or **Play** on the one-screen select) is pressed. While the player is in selection, spawn flow or the scene studio, they sit in a private routing bucket.

## Features

- Full-screen React NUI character select with a live ped preview, create and delete flows. See [UI](./ui.md).
- Job and gang based preview scenes (six bundled, more via config or runtime export). See [Scenes](./scenes.md).
- One-screen select with an arrival camera flight, or the original Continue then spawn carousel. See [Spawn and arrival](./spawn-and-arrival.md).
- In-game scene studio (`/multicharscene`) and staff `/logout`. See [Commands](./commands.md).
- Cross-resource scene registration. See [Exports](./exports.md).
- Events, callbacks and the replicated mode state. See [Events](./events.md).

## Pages

- [Installation](./installation.md) - dependencies, start order, build notes.
- [Configuration](./configuration.md) - every `Config` option.
- [Scenes](./scenes.md) - scene schema, selectors, cues, limits.
- [Spawn and arrival](./spawn-and-arrival.md) - spawn locations, carousel, arrival flight.
- [Commands](./commands.md) - commands and permissions.
- [Exports](./exports.md) - server exports.
- [Events](./events.md) - net events, local events, callbacks, NUI callbacks, state bag.
- [UI](./ui.md) - player controls and the scene studio.
- [Compatibility](./compatibility.md) - qb-multicharacter and qb-spawn protocol, optional integrations.
- [Troubleshooting](./troubleshooting.md) - common problems.

## Database

This resource has no SQL and no tables of its own. Characters are read and written by `kora_core`.
