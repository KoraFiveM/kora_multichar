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
- Cross-resource scene registration. See [API reference](./api/index.md).
- Events, callbacks and the replicated mode state. See [Events](./events.md).

## Documentation map

- [Installation](./installation.md) - install steps, NUI build, dependencies, start order.
- [How to use](./how-to-use.md) - the end-to-end flow, `spawnComplete`, camera and scene system, scene studio, kora_core calls.
- [Commands](./commands.md) - `/multicharscene`, `/logout`, `/closeNUI`, the studio key binding and permissions.
- [API reference](./api/index.md) - module overview.
  - [Scene registry](./api/scene-registry.md) - `RegisterScene` and `UnregisterScene` exports.
- [Configuration](./configuration.md) - every `Config` option.
- [Scenes](./scenes.md) - scene schema, selectors, cues, limits.
- [Spawn and arrival](./spawn-and-arrival.md) - spawn locations, carousel, arrival flight.
- [Events](./events.md) - net events, local events, callbacks, NUI callbacks, state bag.
- [UI](./ui.md) - player controls and the scene studio.
- [Compatibility](./compatibility.md) - qb-multicharacter and qb-spawn protocol, optional integrations.
- [Troubleshooting](./troubleshooting.md) - common problems.

## Database

This resource has no SQL and no tables of its own. Characters are read and written by `kora_core`.
