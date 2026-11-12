---
title: "Scene registry"
sidebar_position: 2
---


# Scene registry

The only public exports kora_multichar offers to other resources: registering and removing character-selection scenes at runtime, for a job or gang resource that wants its own cinematic without editing `Config.scenes` directly. Everything else — character list, preview, creation, spawn — is reached through events and callbacks, most of them kora_core's own `qb-multicharacter:*` compatibility layer (see Compatibility with kora_core above), not through kora_multichar exports.

Namespace: `exports.kora_multichar` · Source: `server.lua`

## Functions

Two exports, both server-only.

### `exports.kora_multichar:RegisterScene(id, definition)`

Registers (or replaces, if the caller already owns it) a character-selection scene at runtime and broadcasts it to every connected client so an active preview can pick it up immediately.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Stable scene id. Must not already be owned by a different resource. |
| `definition` | table | A SceneSchema scene table — same shape as `Config.scenes[id]` and what the scene studio's export produces (`anchor`, `environment`, `character`, `entities`, `cameras`, `timeline`, `selectors`, `priority`, `label`). |

**Returns**

- **ok** — `true` on success.
- **err** — on failure (`false, err`): the id is owned by another resource, the scene registry is full (`Config.sceneLimits.maxScenes`), or the definition failed validation.

**Example**

```lua
-- server script of a job/gang resource, after kora_multichar has started
exports.kora_multichar:RegisterScene('towtruck', {
    label = 'Hayes Auto · Tow Yard',
    priority = 150,
    selectors = { { job = 'tow' } },
    anchor = vector4(438.0, -1017.0, 28.6, 95.0),
    environment = { hour = 17, minute = 0, weather = 'CLEAR' },
    character = { offset = vector4(0.0, 0.0, 0.0, 0.0), scenario = 'WORLD_HUMAN_HAMMERING' },
    entities = {},
    cameras = { { id = 'close', offset = { x = 0.65, y = 2.65, z = 1.68 }, lookAt = { x = 0.0, y = 0.0, z = 1.34 }, fov = 30.0 } },
    timeline = { durationMs = 18000, loop = true, cues = { { at = 0, type = 'camera', camera = 'close' } } },
})
```

**Representative console output**

```text
Server-only export. Ownership is tracked by the calling resource name (`GetInvokingResource()`), so only that resource (or a later call from it) may update or remove it. Bundled and `Config.scenes` entries are owned by kora_multichar itself.
```

### `exports.kora_multichar:UnregisterScene(id)`

Removes a scene this resource previously registered and broadcasts the removal to clients.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | The scene id to remove. |

**Returns**

- **ok** — `true` on success.
- **err** — `false, 'unknown scene'` or `false, 'scene is owned by another resource'`.

**Example**

```lua
exports.kora_multichar:UnregisterScene('towtruck')
```

**Representative console output**

```text
Server-only export. A resource's own scenes are also unregistered automatically when it stops (`onResourceStop`).
```

## Limits and related APIs

Scene definitions are capped by `Config.sceneLimits` (max scenes, peds, vehicles, props, cameras, cues, timeline length). A scene whose anchor, cameras or timeline fail validation is refused rather than partially stored.

## Behaviour details (from the code)

Both exports are server-side and the caller is identified by `GetInvokingResource()`; ownership is enforced on that name.

- `RegisterScene` validates the definition against the [scene schema](../scenes.md) and `Config.sceneLimits`. It fails if the id is owned by another resource or the registry is full (`maxScenes`). Success is broadcast to all clients (`kora_multichar:client:sceneUpsert`), and open character selects re-preview.
- `UnregisterScene` broadcasts the removal (`kora_multichar:client:sceneRemove`). All scenes owned by a resource are removed automatically when that resource stops.
- Scenes from `Config.scenes` are owned by `kora_multichar` itself.

Shorter example with vector values:

```lua
local ok, err = exports.kora_multichar:RegisterScene('taxi_depot', {
    label = 'Downtown Cab Co.', priority = 200,
    selectors = { { job = 'taxi' } },
    anchor = vector4(903.1, -170.2, 74.1, 235.0),
    character = { offset = vector4(0.0, 0.0, 0.0, 0.0) },
    entities = {},
    cameras = {
        { id = 'close', offset = vector3(0.65, 2.65, 1.68), lookAt = vector3(0.0, 0.0, 1.34), fov = 30.0 },
    },
    timeline = { durationMs = 18000, loop = true, cues = {
        { at = 0, type = 'camera', camera = 'close' },
    } },
})
if not ok then print(err) end
```

## FFT export

`fftVersion` and `fftAction` exist only when the FFT hooks are enabled; see [Events](../events.md#fft-hooks).
