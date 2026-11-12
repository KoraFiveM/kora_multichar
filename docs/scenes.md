---
title: Scenes
sidebar_position: 7
---

A scene is the staged backdrop for a character preview: an anchor, the character's position, optional local peds, vehicles and props, cameras and a cue timeline.

## Bundled scenes

`scenes.lua` ships six base-game scenes: a civilian sunset on Vespucci sand with two jet-ski riders (priority 0, the default), a police robbery response at a Strawberry 24/7, an active Pillbox paramedic response, a Benny's mechanic workshop, Ballas at Davis and Vagos at Rancho. Career scenes have priority 200, gang scenes 100. Saved clothing is always used; scenes never force uniforms.

## Selection and resolution

`selectors` is a list of alternatives (OR). Fields inside one selector are conditions (AND): `job`, `gang`, `minGrade`, `maxGrade`, `duty`. Grade limits apply to the job when `job` is set, otherwise to the gang. `duty` is always checked against the job's `onduty`. At least `job` or `gang` is required per selector.

The highest `priority` wins; ties go to the lower scene id. A scene with `enabled = false` is skipped. With no match, `Config.defaultScene` is used, then the first scene by id.

```lua
selectors = {
    { job = 'police', minGrade = 2, duty = true },
    { gang = 'ballas', minGrade = 1 },
}
```

## Schema

Positions are offsets rotated around `anchor` (a vector4), so moving the anchor moves the whole scene. Definitions are data only and are validated on registration and again on the client.

```lua
Config.scenes.example = {
    label = 'Example Service Bay',
    priority = 200,
    selectors = { { job = 'mechanic', minGrade = 1 } },
    anchor = vector4(-211.550, -1324.550, 30.890, 270.000),
    environment = { hour = 14, minute = 30, weather = 'EXTRASUNNY', timecycle = 'scanline_cam_cheap', strength = 0.08 },
    character = {
        offset = vector4(0.0, 0.0, 0.0, 0.0),
        scenario = 'WORLD_HUMAN_HAMMERING', -- or animation = { dict = '...', name = '...', flag = 49 }
    },
    entities = {
        { id = 'project', type = 'vehicle', model = 'sultan', offset = vector4(-4.2, 2.4, 0.0, 90.0),
          vehicle = { engine = false, lights = true, livery = 0, primaryColor = 145, secondaryColor = 145 } },
        { id = 'worker', type = 'ped', model = 's_m_y_xmech_02', offset = vector4(-2.5, 1.2, 0.0, 95.0),
          scenario = 'WORLD_HUMAN_VEHICLE_MECHANIC' },
        { id = 'tools', type = 'prop', model = 'prop_tool_box_04', offset = vector4(2.4, 1.5, 0.0, 0.0) },
    },
    cameras = {
        { id = 'close', offset = vector3(0.65, 2.65, 1.68), lookAt = vector3(0.0, 0.0, 1.34), fov = 30.0,
          dof = { near = 0.8, far = 3.2, strength = 0.65 } },
        { id = 'focal', offset = vector3(7.4, 6.2, 3.25), lookAt = vector3(-2.0, 1.8, 0.8), fov = 41.0, transitionMs = 2100 },
    },
    timeline = {
        durationMs = 18000, loop = true,
        cues = {
            { at = 0, type = 'camera', camera = 'close' },
            { at = 1700, type = 'camera', camera = 'focal', transitionMs = 2100 },
        },
    },
}
```

### Validation rules

- Scene id: 1-48 letters, digits, `_` or `-`. `label` is required (up to 64 bytes). `priority` is an integer.
- `anchor` and `character.offset` are required vector4 values. At least one camera is required.
- `environment.hour` 0-23, `minute` 0-59, `strength` 0-1.
- Entity `type` is `ped`, `vehicle` or `prop`; ids are unique, 1-48 bytes; `model` is a string or number. `snapToWater` is only valid on vehicles. Vehicle state accepts `engine`, `lights`, `siren`, `mutedSiren`, `anchored`, `livery`, colours, `extras` and `doors`.
- A ped can sit in a local vehicle with `seat = { vehicle = 'vehicle_entity_id', index = -1 }`.
- Camera `fov` 10-100, `transitionMs` 0-10000.
- Cue `at` must be within the timeline duration. Supported cue types: `camera`, `animation`, `scenario`, `vehicleState`, `vehicleRoute`, `particle`, `nativeSound`, `entityVisibility`. `vehicleRoute` must target a seated driver ped, with `destination` (offset), `speed` (above 0, at most 80), `drivingStyle`, `stoppingRange` (0-100) and optional `snapToWater`/`snapToGround` (not both).
- Audio accepts only GTA native sound names and sets; there is no URL or file audio.
- Peds, vehicles and props are local and non-networked. A model, animation or particle that fails to stream is skipped; a character or camera failure falls back to the default scene. Land characters and vehicles snap to ground by default; use `snapToGround = false, snapToWater = true` for boats.

## Runtime scenes

Other resources register scenes with [`RegisterScene`](./api/scene-registry.md). Scenes are owned by the registering resource and are removed when it stops.
