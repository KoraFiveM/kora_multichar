---
title: Events
sidebar_position: 9
---

## Local client event

| Event | Arguments | Description |
| --- | --- | --- |
| `kora_multichar:client:spawnComplete` | `isNew` | Fired once the player is in the world: ped placed, revealed and unfrozen, fade-in finished (waits at most 5 s for the fade). `isNew` is true only for a just-created character. |

```lua
AddEventHandler('kora_multichar:client:spawnComplete', function(isNew) end)
```

Use this rather than watching the mode state bag, which clears before the teleport and replicates asynchronously.

## Net events

| Event | Direction | Arguments | Description |
| --- | --- | --- | --- |
| `kora_multichar:server:arrivalEffect` | client to server | `x, y, z` | Reports where the arrival effect played. Validated and relayed; see [Spawn and arrival](./spawn-and-arrival.md). |
| `kora_multichar:client:arrivalEffect` | server to client | `asset, effect, scale, x, y, z` | Play the configured effect. Ignored while in selection. |
| `kora_multichar:client:sceneUpsert` | server to client | `id, definition` | A scene was added or replaced. |
| `kora_multichar:client:sceneRemove` | server to client | `id` | A scene was removed. |
| `kora_multichar:client:openCreator` | server to client | `catalog` | Opens the scene studio. |
| `multichar:client:selectFailed` | server to client | `message` | The server refused a character load. |

Legacy events are listed in [Compatibility](./compatibility.md).

## Callbacks (`Kora.callback`)

| Callback | Arguments | Result |
| --- | --- | --- |
| `kora_multichar:server:getScenes` | none | Copy of the scene registry. |
| `kora_multichar:server:enterMode` | `mode` | `true`, or `false, reason`. Rate limit 8 per 10 s. |
| `kora_multichar:server:leaveMode` | none | `true`. Rate limit 8 per 10 s. |
| `kora_multichar:server:validateNationality` | `value` | `true, value` or `false, message`. Rate limit 8 per 10 s. |
| `qb-multicharacter:server:GetServerLogs` | none | Always an empty table. |

`enterMode` rules: `selection` is refused when already logged in; `spawn` needs an existing session and a logged-in player; `creator` is refused (only the protected command opens it).

## Replicated state

`Player(src).state['kora_multichar:mode']` is `selection`, `spawn` or `creator` during a session, and `false` otherwise (the server writes `false`, not `nil`). Other resources (for example `kora_lib`'s interact and zones modules) read it to stay inactive during cinematic mode.

## NUI callbacks

Internal to the bundled UI: `multichar:preview`, `multichar:createPreview`, `multichar:select`, `multichar:create`, `multichar:delete`, `multichar:disconnect`, `multichar:spawn:list`, `multichar:play`, `multichar:spawn:focus`, `multichar:spawn:choose`, `multichar:spawn:exit` and `multichar:creator:action`. Do not call them from other resources.

## FFT hooks

`fft_hooks.lua` returns immediately unless the convar `fft_kora_hooks` is `true`. When enabled it exports `fftVersion` and `fftAction`, which only work for the `fft` resource with an active `fftSession` state. Actions: `enterMode`, `leaveMode`, `validateNationality`, `scenes`, `serverLogs`. It sends the same callbacks as the client and never logs in, creates or deletes characters.
