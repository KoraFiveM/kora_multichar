---
title: Spawn and arrival
sidebar_position: 8
---

## Spawn locations

`Config.spawns` is an ordered array of entries with `id`, `coords` (vector4), `label`, optional `description` and optional `preview`:

```lua
{
    id = 'harbor',
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

The default config offers Legion Square, Pillbox Hill, Sandy Shores and Paleto Bay. Without `preview`, an elevated camera is derived from the destination.

Offer order is: last location, then `Config.spawns` as declared, then owned properties sorted by label. Owned properties come from the `qb-spawn:server:getOwnedHouses` callback (entries need coordinates).

`Config.defaultSpawn` should stay `Config.spawns[1].coords`. New characters bypass the picker and arrive there.

## One-screen select (default)

With `Config.arrival.enabled = true`, the player picks a character and an arrival point on the same screen and presses **Play**. The list is requested per character (`multichar:spawn:list`) and contains `id`, `label`, `description` and `typeLoc` only; coordinates stay in Lua. "Last Location" is listed without coordinates until login. `multichar:play` is checked against the characters and the arrival list the client built, then logs in with `qb-multicharacter:server:loadUserData`. If the server does not answer within 20 s, or refuses, the Play is released with an error.

The flight (`SceneRuntime.flyToArrival`) lifts out of the scene, cruises while the destination streams, then descends into the location's `preview` shot. The arrival places the ped (plus `Config.arrival.zOffset`) while invisible, fires `QBCore:Server:OnPlayerLoaded`, waits `settleMs`, plays the particle effect, fades the ped in over `pedFadeMs` and blends back to gameplay over `handbackMs`. If the flight cannot run, a plain fade-out, teleport, fade-in spawn is used.

| Option | Default | Purpose |
| --- | --- | --- |
| `Config.arrival.enabled` | `true` | Use the one-screen select. When false: Continue then the spawn carousel. |
| `Config.arrival.skippable` | `true` | Space shortens the camera travel; the destination is still streamed. |
| `Config.arrival.settleMs` | `350` | Invisible wait after placement (0-3000). |
| `Config.arrival.pedFadeMs` | `900` | Ped fade-in (0-5000). |
| `Config.arrival.handbackMs` | `1400` | Camera blend to gameplay (0-5000). |
| `Config.arrival.zOffset` | `-0.08` | Added to the arrival z (-3 to 3). |
| `Config.arrival.ptfx.enabled` | `true` | Play an effect on arrival. |
| `Config.arrival.ptfx.asset` / `effect` | `scr_rcbarry1` / `scr_alien_teleport` | Particle asset and effect. |
| `Config.arrival.ptfx.scale` / `zOffset` | `1.0` / `0.0` | Size and height offset. |
| `Config.arrival.ptfx.releaseAfterMs` | `4000` | Used when releasing the effect (not registered with `Kora.config`). |
| `Config.arrival.ptfx.synced` | `true` | Nearby players see the effect. |
| `Config.arrival.ptfx.syncRadius` | `150.0` | Visibility radius in metres (10-500). |

With `synced`, the arriving client sends only a position to `kora_multichar:server:arrivalEffect`. The server requires a logged-in player, finite numbers, a position within 25 m of the server-known ped, at most one report per 5 s, and relays to players in the same routing bucket within `syncRadius` the asset and effect from its own config. Receiving clients ignore the event during character select.

New characters take the same flight to `Config.defaultSpawn`. Characters routed through `qb-apartments`, and the legacy brand-new-character picker, keep the carousel.

## Spawn carousel (arrival disabled or apartments)

The carousel shows a live preview of each location. Rapid switching is limited by `Config.spawnSelect`:

| Option | Default | Purpose |
| --- | --- | --- |
| `switchCooldownMs` | `800` | Minimum gap between switches (0 disables). Enforced in the UI and again in Lua. |
| `settleMs` | `1000` | Dwell time before the camera flies to a location (0 flies on every switch). |
| `lockWhileMoving` | `true` | Ignore switching while the camera flies. |
| `hints` | see file | Text of the key hint bar (`previous`, `next`, `preview`, `flying`, `spawn`). |

`Config.spawnFlight` controls the cinematic: `liftHeight` (130), `minAltitude` (180), `maxAltitude` (420), `liftDurationMs` (900), `descentDurationMs` (1450), `minTravelDurationMs` (1400), `maxTravelDurationMs` (4200), `unitsPerSecond` (650). The world is streamed by parking the hidden, frozen ped at the preview point; its original position is restored when the mode ends. The player always sees the location they chose; there is no fallback "safe spot".

`multichar:spawn:previewLive` tells the UI the camera is live so the loading cover can drop; `multichar:spawn:previewStage` names what is being waited on.

## New characters

`Config.newCharacter.resetAppearance` (default `true`) dresses a new character in `kora_clothing`'s starter outfit before the first spawn, if `kora_clothing` is started.

## Isolation and cleanup

Selection, spawn and studio sessions use a private routing bucket (see `Config.buckets`). Cleanup removes cameras, focus, load scenes, entities, particles, sounds, weather and time overrides, NUI focus, hidden or frozen ped state and the replicated mode on success, errors, disconnect, studio close or resource stop.
