---
title: UI
sidebar_position: 10
---

The NUI is a React/Vite app in `web/`, served from `web/build/index.html`. The resource calls `exports.kora_core:claimUI()` and uses the raw NUI natives for messaging.

## Character select

- Left/right arrows, A/D, mouse buttons and controller input move through characters. Preview changes are debounced (120 ms) and stale responses are discarded.
- The compact card shows name and career; the dossier adds grade, gang and rank, cash, bank, birth date, nationality and citizen ID. Card titles are configurable (`Config.ui.profile`).
- With `Config.arrival.enabled`: up/down arrows change arrival point, Enter plays. Otherwise **Continue** logs in and the spawn carousel opens (Enter, A/D, arrows; Escape in the carousel only shows "Choose a spawn location to continue").
- Delete is secondary and requires typing the exact character name.
- Create Identity takes first name, last name, a real non-future `YYYY-MM-DD` birth date, a body model (male or female freemode) and nationality. Slot, phone, job, gang and money are not client-chosen; `kora_core` validates again server-side. Creation is blocked at the character cap (default 5, or the value from `qb-multicharacter:server:GetNumberOfCharacters`).
- Disconnect triggers `qb-multicharacter:server:disconnect`.

## Scene studio

Open with `/multicharscene` (see [Commands](./commands.md)). It can create, load, duplicate and edit metadata, selectors, environment, character placement, entities, cameras and timeline cues.

- **Tab** toggles between the inspector and freecam (Kora freecam: mouse look, WASD, up and down keys, Shift boost; instructional buttons show the bindings).
- Placement and camera capture use crosshair raycasts and store anchor-relative coordinates.
- Timeline: cue editing, scrubbing, loop and live preview. Validate checks the draft against the scene schema.
- **Copy Config** and **Copy Registration** produce sorted Lua with three-decimal coordinates and copy it to the clipboard.

The studio never writes files or a database; paste the output into `scenes.lua`/`Config.scenes` or into a `RegisterScene` call after review.
