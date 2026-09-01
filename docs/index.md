---
layout: default
title: qbmultichar
---

Cinematic character selection, live spawn previews, and an in-game scene
studio for qbcore. It fully replaces both legacy UIs and keeps the upstream
`qb-multicharacter` and `qb-spawn` event/callback protocols.

Selecting a character only previews their saved appearance. The character is
not logged in until **Continue** is pressed. Once logged in, the player remains
hidden in an isolated routing bucket while the spawn carousel streams and
shows each real destination.

## Requirements

- [qblib](https://qbcore2.github.io/qblib/)
- [qbcore](https://qbcore2.github.io/qbcore/)
- [qbclothing](https://qbcore2.github.io/qbclothing/) — optional, but the
  supported saved-clothing and tattoo provider

```cfg
ensure qbsql
ensure qblib
ensure qbcore
ensure qbclothing
ensure qbmultichar
```

No database migration is needed. The compiled React/Vite NUI is committed in
`web/build`; rebuild it after frontend changes with `npm install && npm run
build` from the `web` directory.

## Player experience

- Left/right, A/D, mouse controls, and relayed controller controls move through
  the carousel. Preview changes are debounced by 120 ms and stale responses
  are discarded.
- The compact card shows name and career. The dossier adds grade, gang/rank,
  cash, bank, birth date, nationality, and citizen ID.
- **Continue** is the only login action. Deletion is secondary and requires the
  exact visible character name.
- Creation accepts first name, last name, real non-future `YYYY-MM-DD` birth
  date, male/female freemode body model, and nationality. qbcore validates and
  normalizes these again server-side; slot, phone, starting job/gang, and money
  are never client-selected.
- Spawn choice is mandatory after an existing character loads. Fixed, last,
  and future property locations all use streamed live cameras. The first view
  stays covered while it loads; subsequent choices lift from the current shot,
  cruise at a distance-scaled altitude while the destination streams, and dive
  along the authored destination camera's approach. `Config.spawnFlight`
  controls altitude, speed, and the three transition timings. A bounded
  ten-second load falls back behind a blackout to a safe overview camera.
- New characters use the same mandatory carousel (including a **First
  Arrival** option). qbclothing's mandatory first-character creator waits for
  the chosen spawn and complete cinematic cleanup before opening.

The server publishes `LocalPlayer.state['qbmultichar:mode']` as `selection`,
`spawn`, `creator`, or `nil`. qbhud observes it and stays hidden until the
cinematic mode is completely cleaned up.

## Bundled scenes and resolution

Six base-game-only scenes ship in `scenes.lua`: a civilian sunset scene on
dry Vespucci sand with two moving local jet-ski riders, a police gas-station
robbery response at the Strawberry 24/7, an active outdoor Pillbox paramedic
response with CPR, patient, stretcher, and ambulance,
mechanic/Benny's, Ballas/Davis, and Vagos/Rancho. Career
scenes have priority 200, gang scenes 100, and the civilian fallback 0. Saved
clothing is always used; scenes never force uniforms.

`selectors` is an array of OR alternatives. Fields inside one selector are AND
conditions. `minGrade`/`maxGrade` apply to `job` when present, otherwise to
`gang`; `duty` always checks the job. The highest priority match wins, equal
priorities sort by scene ID, and `Config.defaultScene` is the fallback.

```lua
selectors = {
    { job = 'police', minGrade = 2, duty = true }, -- alternative one
    { gang = 'ballas', minGrade = 1 },             -- OR alternative two
}
```

## Scene schema

All positions are local offsets rotated around `anchor`, so moving the anchor
relocates the whole composition. Definitions are data only and are validated
on both registration and use.

```lua
Config.scenes.example = {
    label = 'Example Service Bay',
    priority = 200,
    selectors = { { job = 'mechanic', minGrade = 1 } },
    anchor = vector4(-211.550, -1324.550, 30.890, 270.000),

    environment = {
        hour = 14, minute = 30, weather = 'EXTRASUNNY',
        timecycle = 'scanline_cam_cheap', strength = 0.08,
    },

    character = {
        offset = vector4(0.000, 0.000, 0.000, 0.000),
        scenario = 'WORLD_HUMAN_HAMMERING',
        -- or animation = { dict = '...', name = '...', flag = 49 }
    },

    entities = {
        {
            id = 'project', type = 'vehicle', model = 'sultan',
            offset = vector4(-4.200, 2.400, 0.000, 90.000),
            vehicle = {
                engine = false, lights = true, siren = false,
                mutedSiren = true, livery = 0,
                primaryColor = 145, secondaryColor = 145,
                extras = { [1] = true }, doors = { [4] = true },
            },
        },
        {
            id = 'worker', type = 'ped', model = 's_m_y_xmech_02',
            offset = vector4(-2.500, 1.200, 0.000, 95.000),
            scenario = 'WORLD_HUMAN_VEHICLE_MECHANIC',
        },
        {
            id = 'tools', type = 'prop', model = 'prop_tool_box_04',
            offset = vector4(2.400, 1.500, 0.000, 0.000),
        },
    },

    cameras = {
        {
            id = 'close',
            offset = vector3(0.650, 2.650, 1.680),
            lookAt = vector3(0.000, 0.000, 1.340),
            fov = 30.0,
            dof = { near = 0.8, far = 3.2, strength = 0.65 },
        },
        {
            id = 'focal',
            offset = vector3(7.400, 6.200, 3.250),
            lookAt = vector3(-2.000, 1.800, 0.800),
            fov = 41.0, transitionMs = 2100,
        },
        {
            id = 'establishing',
            offset = vector3(11.988, 10.044, 5.600),
            lookAt = vector3(-2.000, 1.800, 0.800),
            fov = 50.0, transitionMs = 2400,
        },
    },

    timeline = {
        durationMs = 18000, loop = true,
        cues = {
            { at = 0, type = 'camera', camera = 'close' },
            { at = 1700, type = 'camera', camera = 'focal', transitionMs = 2100 },
            { at = 5200, type = 'camera', camera = 'establishing', transitionMs = 2400 },
            { at = 6500, type = 'vehicleState', target = 'project', lights = true },
            { at = 7000, type = 'particle', target = 'project', asset = 'core', effect = 'ent_sht_electrical_box', scale = 0.55, durationMs = 2200 },
            { at = 7200, type = 'nativeSound', target = 'project', name = 'Drill', set = 'DLC_HEIST_FLEECA_SOUNDSET' },
            { at = 9400, type = 'camera', camera = 'focal', transitionMs = 2200 },
            { at = 14800, type = 'camera', camera = 'close', transitionMs = 1900 },
        },
    },
}
```

Supported cue types are `camera`, `animation`, `scenario`, `vehicleState`,
`vehicleRoute`, `particle`, `nativeSound`, and `entityVisibility`. A
`vehicleRoute` targets a seated driver ped and accepts a relative
`destination`, `speed`, `drivingStyle`, `stoppingRange`, and optional
`snapToWater`; it uses the same
timeline scheduler as every other cue. Audio deliberately accepts
only GTA native sound names and sound sets; there is no URL/file audio field.
NPCs, vehicles, and props are local and non-networked. An individual model,
animation, or particle that does not stream is skipped; character/camera
failure falls back to the neutral scene. Camera paths are capsule-tested
against map geometry and automatically reframe around obstructions. Land
characters and vehicles snap to streamed ground by default. Use
`snapToGround = false, snapToWater = true` for boats and jet skis. A local ped
can be staged in a local vehicle with
`seat = { vehicle = 'stable_vehicle_id', index = -1 }`.

Default limits in `Config.sceneLimits` are 64 registered scenes, 8 NPCs, 6
vehicles, 24 props, 8 cameras, 64 cues, a 120-second timeline, and a ten-second
stream timeout.

## Runtime scene exports

Runtime scenes are owner tracked. Only the resource that registered a scene
may replace or remove it, and all of its scenes disappear automatically when
that resource stops. Changes are broadcast to connected selectors.

```lua
-- server, in another resource
local ok, err = exports.qbmultichar:RegisterScene('taxi_depot', {
    label = 'Downtown Cab Co.', priority = 200,
    selectors = { { job = 'taxi' } },
    anchor = vector4(903.100, -170.200, 74.100, 235.000),
    character = { offset = vector4(0.000, 0.000, 0.000, 0.000) },
    entities = {},
    cameras = {
        { id = 'close', offset = vector3(0.650, 2.650, 1.680), lookAt = vector3(0.000, 0.000, 1.340), fov = 30.0 },
        { id = 'focal', offset = vector3(-7.000, 6.800, 3.350), lookAt = vector3(0.000, 1.500, 0.900), fov = 43.0, transitionMs = 2100 },
        { id = 'establishing', offset = vector3(-11.340, 11.020, 5.700), lookAt = vector3(0.000, 1.500, 0.900), fov = 52.0, transitionMs = 2400 },
    },
    timeline = { durationMs = 18000, loop = true, cues = {
        { at = 0, type = 'camera', camera = 'close' },
        { at = 1700, type = 'camera', camera = 'focal', transitionMs = 2100 },
        { at = 5200, type = 'camera', camera = 'establishing', transitionMs = 2400 },
        { at = 9400, type = 'camera', camera = 'focal', transitionMs = 2200 },
        { at = 14800, type = 'camera', camera = 'close', transitionMs = 1900 },
    } },
})
if not ok then print(err) end

exports.qbmultichar:UnregisterScene('taxi_depot')
```

### `RegisterScene(sceneId, definition)`

Returns `true`, or `false, error`. Scene IDs contain 1–48 letters, numbers,
underscores, or hyphens.

### `UnregisterScene(sceneId)`

Returns `true`, or `false, error`. Ownership is checked server-side.

## Scene Studio

Admins and gods can open `/multicharscene`. The permission check is
server-side and cascading. The studio can create, load/duplicate, and edit
metadata, selectors, environment, character placement, local entities,
cameras, and timeline cues.

- Press **Tab** to switch between the themed inspector and freecam.
- Freecam uses mouse look, WASD, Q/E vertical movement, and Shift boost.
- Placement and camera capture use crosshair raycasts and store relative
  coordinates.
- Timeline controls support cue editing, scrubbing, looping, and live preview.
- **Copy Config** and **Copy Registration** generate stable, sorted Lua with
  three-decimal coordinates through qblib's clipboard support.

The studio never writes resource files or a database. Paste the copied output
into configuration or another resource after reviewing it.

## Spawn configuration

`Config.spawns` remains compatible with `{ coords, label }` and adds
`description` plus optional live-preview data:

```lua
Config.spawns.harbor = {
    coords = vector4(-800.0, -1500.0, 1.6, 110.0),
    label = 'Harbor',
    description = 'Arrive on the waterfront.',
    preview = {
        camera = vector3(-780.0, -1480.0, 18.0),
        lookAt = vector3(-800.0, -1500.0, 2.0),
        fov = 45.0,
        environment = { hour = 6, minute = 30, weather = 'CLEAR' },
    },
}
```

Without `preview`, a safe elevated camera is derived from the destination.
Future housing integrations can return coordinate-bearing owned houses through
the existing `qb-spawn:server:getOwnedHouses` callback and they will appear
automatically.

## Isolation and cleanup

Selection/spawn sessions use bucket `1100000 + source`; creator sessions use
`1200000 + source`. The previous bucket is restored through qbcore's bucket
compatibility API. One cleanup path tears down cameras, focus, load scenes,
entities, particles, native sounds, weather/time/timecycle overrides, NUI
focus, hidden/frozen ped state, and the replicated mode on success, errors,
disconnect, creator close, or resource stop.

## Legacy compatibility

The resource provides `qb-multicharacter` and `qb-spawn` and continues to use
the established callbacks/events, including:

```lua
'qb-multicharacter:server:setupCharacters'
'qb-multicharacter:server:GetNumberOfCharacters'
'qb-multicharacter:server:getSkin'
'qb-multicharacter:server:loadUserData'
'qb-multicharacter:server:createCharacter'
'qb-multicharacter:server:deleteCharacter'
'qb-spawn:server:getOwnedHouses'
'qb-spawn:client:setupSpawns'
'qb-spawn:client:openUI'
```

qbclothing protects preview appearance reads with qbcore ownership checks,
soft-delete filtering, sanitization, rate limiting, and a per-selection cache.
