---
title: Configuration
sidebar_position: 6
---

All options live in `config.lua`. `shared/config_registration.lua` registers many of them with `Kora.config` so they can be edited through kora's config tooling; options marked "live" there apply the next time character select opens (or the next session or arrival, as noted). Options without a registration (for example `Config.spawns`, `Config.spawnFlight`, `Config.creator`, `Config.logout`) are read from `config.lua` only.

## Selection and UI

| Option | Default | Purpose |
| --- | --- | --- |
| `Config.defaultScene` | `civilian` | Scene used when no selector matches. |
| `Config.cameraMode` | `focus` | `focus` keeps the camera on the previewed ped; `cycle` loops the scene timeline's cameras. |
| `Config.previewWatchdogMs` | `15000` | How long the UI waits on a preview before giving up with an error. `0` disables. |
| `Config.ui.closeCreateOnBackdrop` | `false` | Clicking outside Create Identity closes it. |
| `Config.ui.confirmDiscardOnClose` | `true` | Asks before discarding typed details. |
| `Config.ui.confirmDisconnect` | `true` | Sent to the UI; not registered with `Kora.config`. |
| `Config.ui.brandName` | `Kora` | Brand text (1-32 characters). |
| `Config.ui.showNewSlotBadge` | `false` | NEW badge on the free slot. |
| `Config.ui.profile.*` | see file | Card titles (`career`, `affiliation`, `finances`, `birthDate`, `nationality`, `citizenId`) and optional description lines for the last three. An empty description hides the line. |
| `Config.nationalities` | 58 entries | Dropdown choices. |
| `Config.defaultNationality` | `American` | Preselected value. |
| `Config.allowFreeTextNationality` | `false` | Free text; server accepts any 2-32 character value. |

The server validates nationality through `kora_multichar:server:validateNationality`: with a non-empty list and free text off the value must be in the list; otherwise it must be 2-32 characters. The UI font is Onest (SIL OFL 1.1, licence in `web/src/fonts`).

## Scenes and limits

`Config.scenes` holds scene definitions (filled by `scenes.lua`); see [Scenes](./scenes.md).

| Option | Default |
| --- | --- |
| `Config.sceneLimits.maxScenes` | 64 |
| `Config.sceneLimits.maxPeds` | 8 |
| `Config.sceneLimits.maxVehicles` | 6 |
| `Config.sceneLimits.maxProps` | 24 |
| `Config.sceneLimits.maxCameras` | 8 |
| `Config.sceneLimits.maxCues` | 64 |
| `Config.sceneLimits.maxTimelineMs` | 120000 |
| `Config.sceneLimits.streamTimeoutMs` | 20000 |
| `Config.sceneLimits.worldStreamTimeoutMs` | 8000 (ceiling for world streaming, not a target) |

## Routing buckets

| Option | Default | Purpose |
| --- | --- | --- |
| `Config.buckets.enabled` | `true` | Isolate sessions in a personal bucket. When false the player is never moved. |
| `Config.buckets.disablePopulation` | `true` | Disable ambient peds and vehicles in that bucket. |
| `Config.buckets.selectionBase` | `1100000` | Selection and spawn bucket is this plus the player's server id. |
| `Config.buckets.creatorBase` | `1200000` | Scene studio bucket base. |

## Spawn and arrival

`Config.spawns`, `Config.defaultSpawn`, `Config.spawnFlight`, `Config.spawnSelect`, `Config.arrival` and `Config.newCharacter` are documented in [Spawn and arrival](./spawn-and-arrival.md).

## Staff commands

```lua
Config.logout = { enabled = true, command = 'logout', minimumPermission = 'admin' }
Config.creator = { enabled = true, command = 'multicharscene', minimumPermission = 'admin' }
```

`Config.creator` also holds `moveSpeed` (6.0), `fastMultiplier` (3.0), `lookSensitivity` (5.0), `placementDistance` (8.0) for the freecam, and `library` (lists of `{ model, label }` pairs for `ped`, `vehicle` and `prop` that the studio offers). See [Commands](./commands.md).
