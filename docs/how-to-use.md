---
title: "How to use"
sidebar_position: 3
---


# How to use

Kora Multichar owns presentation: the character list, the live preview camera and scene, character creation and deletion requests, the staff scene studio, and the spawn-location carousel. It is not the authority on whether a character may be created or deleted, or what a character's saved data is — that lives in kora_core, which it reaches only through kora_core's legacy `qb-multicharacter:*` compatibility events and callbacks (see Compatibility with kora_core).

## The end-to-end flow

1. **Boot** — On resource start the client calls `exports.kora_core:claimUI()` so kora_core's own built-in default character flow stays off, waits for a stable player ped and a real server id, then fires `qb-multicharacter:client:chooseChar`.

2. **Character select** — That event enters `selection` mode (a server callback that isolates the player in a personal routing bucket), fetches the character list and scene catalog, and shows the NUI. Hovering or clicking a character asks the server for that character's skin and plays the matching cinematic scene (see Camera and scene system).

3. **Create or delete** — Create Identity validates locally, asks the server to validate the nationality (`kora_multichar:server:validateNationality`), then sends the new character to kora_core (`qb-multicharacter:server:createCharacter`). Delete asks kora_core directly (`qb-multicharacter:server:deleteCharacter`) and refreshes the list on success. kora_multichar never writes a character row itself.

4. **Load** — Choosing a character sends `qb-multicharacter:server:loadUserData`; kora_core logs the character in and kora_core's compat layer then fires the spawn events below.

5. **Spawn selection** — kora_core's compat fires `qb-spawn:client:setupSpawns` (with the loaded character data) and `qb-spawn:client:openUI`. spawn.lua builds the location carousel — last location (or the configured first-arrival point for a new character), the fixed `Config.spawns` list, owned houses (`qb-spawn:server:getOwnedHouses`) and, with qb-apartments running, starting apartments — and enters `spawn` mode. Choosing a location (or a brand-new character's automatic default) ends the cinematic, teleports and resurrects the player ped, and fires the server event `QBCore:Server:OnPlayerLoaded`.

6. **Spawn complete** — Once the screen has actually faded back in, the client fires `kora_multichar:client:spawnComplete(isNew)` — see below.

## kora_multichar:client:spawnComplete

A client event other resources can listen for to know the player is truly in the world (ped placed, resurrected, visible, unfrozen, collision and fade-in done) rather than merely logged in. kora_loading listens for it to dismiss its loading screen.

```lua
-- client script of any resource that must wait for the player to actually be in the world
AddEventHandler('kora_multichar:client:spawnComplete', function(isNew)
    if isNew then
        -- brand-new character: appearance was just reset to kora_clothing's starter outfit
    end
end)
```

- Fired from `finishAt(coords, forceNew)` in client.lua, the single finalisation path shared by the fixed-location, last-location and spawn-carousel flows (`multicharFinishSpawn`).
- It fires from a bounded wait loop (`announceSpawnComplete`) that polls `IsScreenFadedIn()` for up to 5 seconds after `DoScreenFadeIn(500)`, so it fires once the fade has actually completed or after that 5-second ceiling, whichever comes first — never before the ped has been moved, resurrected, revealed, unfrozen and un-collided.
- It is deliberately not tied to the `kora_multichar:mode` state bag clearing: that clears earlier, before the teleport, and replicates asynchronously, which would wake listeners while the ped was still being placed.
- `isNew` is `true` only for a just-created character's first spawn (set when kora_core's `qb-multicharacter:client:closeNUIdefault` lands, or passed through from the spawn carousel for a new character's chosen location).

## Camera and scene system

Character-select previews and the spawn carousel both run through a disposable, client-local "scene" built from the SceneSchema format (shared/scene.lua) and executed by SceneRuntime (scene.lua). A scene describes an anchor point, world time/weather, the previewed character's pose, any extra peds/vehicles/props, named cameras, and a timed cue timeline (camera cuts, animations, particles, native sounds, vehicle routes/state).

- `Config.cameraMode = 'focus'` (default) keeps the camera settled on the previewed ped and only moves it when the selection changes; scene timeline camera cues are ignored (every other cue type still plays). `'cycle'` is the original behaviour: the timeline keeps cutting between its close/focal/establishing cameras on a loop.
- Six bundled scenes ship in scenes.lua (`civilian` — the default fallback, `police`, `ambulance`, `mechanic`, `ballas`, `vagos`), matched to a character by job or gang `selectors` and a `priority` (highest wins). Add more via `Config.scenes` or `exports.kora_multichar:RegisterScene` — a selector-matched scene always outranks the `civilian` default.
- Character select and the spawn carousel each isolate the player in their own personal routing bucket (`Config.buckets.selectionBase` / a per-player offset) with ambient population optionally disabled, and restore the player's previous bucket when the session ends. kora_clothing's first-character fitting room runs afterward, in its own bucket, not inside this session.
- The spawn carousel additionally flies a cinematic camera between chosen locations (`Config.spawnFlight`): lift away, cruise at a distance-scaled altitude while the destination streams in, then descend along the destination's approach vector.

## The scene studio

An in-game visual editor for authoring scenes, gated behind a command and a permission level.

- Opened with `/multicharscene` (configurable via `Config.creator.command`), restricted to `Config.creator.minimumPermission` (default `admin`) through kora_lib's permission gateway. It only opens for a player who already has a character loaded.
- A freecam (kora_lib's `Kora.freecam`) lets staff place the character anchor, extra entities and cameras, scrub the timeline, and validate the draft against the same limits the runtime enforces (`Config.sceneLimits`).
- Export copies ready-to-paste Lua to the clipboard: either a `Config.scenes[id] = { ... }` block, or an `exports.kora_multichar:RegisterScene(id, { ... })` call for a resource that wants to register its own scene at boot. It never writes a file or a database itself.

## Compatibility with kora_core (character ownership lives there, not here)

kora_multichar never reads or writes character rows directly. Every character-lifecycle action goes through kora_core's `qb-multicharacter:*` compatibility events/callbacks (implemented in kora_core's `compat/server/qb-multicharacter.lua`), which kora_multichar's manifest comment calls "the one character lifecycle transport exposed to other resources". The exact calls it makes:

- `Kora.callback.trigger('qb-multicharacter:server:setupCharacters')` — fetch the character list (kora_core: `Core.multichar.getCharacters`).
- `Kora.callback.trigger('qb-multicharacter:server:GetNumberOfCharacters')` — the character-slot cap.
- `Kora.callback.trigger('qb-multicharacter:server:getSkin', citizenid)` — appearance for the preview (kora_core's compat answers `nil` here, so without an appearance module the preview falls back to a default gendered model; when kora_clothing is started it overrides this callback and supplies the saved appearance).
- `TriggerServerEvent('qb-multicharacter:server:loadUserData', { citizenid })` — select/log in a character (kora_core: `Core.multichar.selectCharacter`).
- `TriggerServerEvent('qb-multicharacter:server:createCharacter', data)` — create a character (kora_core: `Core.player.createCharacter`; kora_core computes the slot and enforces the character limit server-side).
- `Kora.callback.trigger('qb-multicharacter:server:deleteCharacter', citizenid)` — delete a character (kora_core: `Core.multichar.deleteCharacter`).
- `TriggerServerEvent('qb-multicharacter:server:disconnect', reason)` — drop the player (kora_core: `DropPlayer`).
- It also listens for kora_core's replies/events: `qb-multicharacter:client:chooseChar`, `qb-multicharacter:client:closeNUI`, `qb-multicharacter:client:closeNUIdefault` (new character's immediate spawn), `qb-multicharacter:client:spawnLastLocation`, `multichar:client:selectFailed`, and (for the spawn carousel) kora_core's compat relaying `qb-spawn:client:setupSpawns` / `qb-spawn:client:openUI` once a character is loaded.
- It also watches the replicated `kora_core:loggedIn` state bag (owned by kora_core) to return to character select after any logout, from any source — its own `/logout` command, an admin tool, or a delete of a live character.
- Everything kora_multichar itself owns — routing-bucket isolation, the preview scene/camera, the spawn carousel and its camera flight, the scene studio, and firing `kora_multichar:client:spawnComplete` — has no kora_core involvement at all.
