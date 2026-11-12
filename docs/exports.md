---
title: Exports
sidebar_position: 7
---

Both exports are server-side. The caller is identified by `GetInvokingResource()`; ownership is enforced on that name.

## `RegisterScene(sceneId, definition)`

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

Returns `true`, or `false, error`. The definition is validated against the [scene schema](./scenes.md) and `Config.sceneLimits`. It fails if the id is owned by another resource or the registry is full (`maxScenes`). Success is broadcast to all clients (`kora_multichar:client:sceneUpsert`), and open character selects re-preview.

## `UnregisterScene(sceneId)`

```lua
exports.kora_multichar:UnregisterScene('taxi_depot')
```

Returns `true`, or `false, error` (`unknown scene`, or owned by another resource). Removal is broadcast. All scenes owned by a resource are removed automatically when that resource stops.

Scenes from `Config.scenes` are owned by `kora_multichar` itself.

## FFT export

`fftVersion` and `fftAction` exist only when the FFT hooks are enabled; see [Events](./events.md#fft-hooks).
