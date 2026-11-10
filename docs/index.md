---
layout: default
title: kora_multichar
---

Cinematic character selection, live spawn previews, and an in-game scene
studio for kora_core. It fully replaces both legacy UIs and keeps the upstream
`qb-multicharacter` and `qb-spawn` event/callback protocols.

Selecting a character only previews their saved appearance. The character is
not logged in until **Continue** is pressed. Once logged in, the player remains
hidden in an isolated routing bucket while the spawn carousel streams and
shows each real destination.

## Requirements

- [kora_lib](https://qbcore2.github.io/kora_lib/)
- [kora_core](https://qbcore2.github.io/kora_core/)
- [kora_clothing](https://qbcore2.github.io/kora_clothing/) — optional, but the
  supported saved-clothing and tattoo provider

```cfg
ensure kora_sql
ensure kora_lib
ensure kora_core
ensure kora_clothing
ensure kora_multichar
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
  date, male/female freemode body model, and nationality. kora_core validates and
  normalizes these again server-side; slot, phone, starting job/gang, and money
  are never client-selected.
- Nationality is a dropdown of `Config.nationalities`; `Config.defaultNationality`
  is preselected and the server (`kora_multichar:server:validateNationality`)
  rejects values outside the list. Set `Config.allowFreeTextNationality = true`
  (or an empty list) for a free-text field. `Config.ui.brandName` (default
  `Kora`) sets the brand text and `Config.ui.showNewSlotBadge` (default off)
  shows the NEW badge on the free slot. `Config.ui.profile` sets the title of every
  Profile card and the optional description line of Birth date (default none),
  Nationality (`Place of origin`) and Citizen ID (default none); an empty
  description hides the line. The UI font is Onest, bundled in
  `web/src/fonts` (SIL OFL 1.1, licence alongside); override `--font-sans` in
  `web/src/styles.css` to change it.
- Spawn choice is mandatory after an existing character loads. Fixed, last,
  and future property locations all use streamed live cameras. The first view
  stays covered while it loads; subsequent choices lift from the current shot,
  cruise at a distance-scaled altitude while the destination streams, and dive
  along the authored destination camera's approach. `Config.spawnFlight`
  controls altitude, speed, and the three transition timings. A bounded
  ten-second load falls back behind a blackout to a safe overview camera.
- Rapid switching is rate-limited by `Config.spawnSelect.switchCooldownMs`
  (default 800; 0 disables) for the arrow buttons, arrow keys and A/D, in the
  UI and again in Lua between flights. Browsing only changes the label: the
  camera flight, world stream and ped anchor start once the player has stayed
  on a location for `Config.spawnSelect.settleMs` (default 1000; 0 flies on
  every switch), and each further switch restarts that wait. With
  `Config.spawnSelect.lockWhileMoving` (default true) switching is ignored
  while the camera flies, until it arrives. The cruise camera height is absolute (the previous
  point's z plus `Config.spawnFlight` altitude), never added to the camera's
  current height. The key hint bar text is `Config.spawnSelect.hints`.
- Locations are offered in a fixed order: last location, then `Config.spawns`
  exactly as declared, then owned property by label.
- New characters bypass the spawn carousel and land immediately at
  `Config.defaultSpawn`, which **is** `Config.spawns[1].coords` — the first
  location the picker offers and where a new character wakes up are one
  decision, so reordering that list moves both. kora_clothing's mandatory
  first-character creator waits for that spawn to complete before opening.
- A new character never inherits the previous character's clothes. While the
  screen is faded out, before the first spawn, the ped is dressed in
  kora_clothing's starter outfit (`exports.kora_clothing:applyStarterAppearance()`,
  configured by kora_clothing `Config.starterOutfit`), so the creator opens on
  that look. Controlled by `Config.newCharacter.resetAppearance` (default
  `true`; needs kora_clothing running).
- The UI never reports a working preview as a broken one. It sizes its own
  timeout from the budget Lua ships with the spawn payload
  (`SceneRuntime.spawnPreviewBudgetMs`, derived from the flight timings and the
  world-stream timeout), and a preview abandoned because the player clicked
  elsewhere reports `superseded` and raises no toast. Only a camera that cannot
  be created or a destination that cannot be streamed is reported.
- **The "Scouting your arrival" cover comes down on Lua's own signal, not on
  the focus callback's answer.** `multichar:spawn:previewLive` is sent the
  moment the spawn camera is active and the world revealed; the callback only
  answers once the whole preview has settled, and the budget above is over a
  minute on default config. Releasing the cover on that answer left a player
  sitting on a loading panel with a finished camera behind it — the "stuck on
  Scouting your arrival" report. The callback still resolves afterwards and
  still decides whether a failure is worth a toast, and a timeout for a preview
  whose camera already went live is silent, because the player can see it did.
- While the cover is up, `multichar:spawn:previewStage` names what is being
  waited on. Cosmetic, but a fixed line for the whole wait is indistinguishable
  from a hung panel.
- **The world is streamed by parking the (already hidden) player ped at the
  preview point**, not by a bare focus position. The streamer loads the map
  around the local player ped and only weakly around a focus, so the previous
  approach — `SetFocusPosAndVel` plus a load scene, with the ped still wherever
  it happened to be — waited a long time and then showed a black world, because
  nothing had actually streamed at the camera. The ped is frozen, invisible and
  collision-free for the whole cinematic mode, so moving it costs nothing
  visually; `beginMode` records where it started and `endMode` puts it back, so
  a player who disconnects mid-selection does not persist a preview coordinate
  as their position.
- The load scene is kept as an accelerant only. It is a hint, not a gate: the
  wait ends as soon as `HasCollisionLoadedAroundEntity` reports the area is
  there, and `Config.sceneLimits.worldStreamTimeoutMs` (8s) is a ceiling rather
  than a target.
- **There is no "safe spot" diversion.** The player is always shown the location
  they picked. A destination that has not finished streaming when the camera
  arrives pops its last props in behind the shot, which is a far better answer
  than showing someone a city spawn they did not choose.

The server publishes `LocalPlayer.state['kora_multichar:mode']` as `selection`,
`spawn`, `creator`, or `nil`. kora_hud observes it and stays hidden until the
cinematic mode is completely cleaned up.

## Spawn completion

```lua
AddEventHandler('kora_multichar:client:spawnComplete', function(isNew) end)
```

A client-local event fired once the player is genuinely in the world: the ped
has been placed, resurrected, revealed and unfrozen, and the fade-in has
finished. `isNew` is `true` only for a character that was just created.

Use this, not the cleared `kora_multichar:mode` state bag, to gate anything that
must not run before the player can see themselves. The mode is cleared *before*
the teleport (the bucket has to be restored first) and its clear replicates
asynchronously on top of that, so a watcher of the bag can wake mid-teleport.
That is what used to put kora_clothing's first-character fitting room on screen
ahead of the spawn.

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
local ok, err = exports.kora_multichar:RegisterScene('taxi_depot', {
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

exports.kora_multichar:UnregisterScene('taxi_depot')
```

### `RegisterScene(sceneId, definition)`

Returns `true`, or `false, error`. Scene IDs contain 1–48 letters, numbers,
underscores, or hyphens.

### `UnregisterScene(sceneId)`

Returns `true`, or `false, error`. Ownership is checked server-side.

## Staff logout

`/logout` drops the staff member's character while keeping their connection,
putting them straight back into character select. It is gated exactly like the
scene studio: `Config.logout.minimumPermission` (default `admin`), resolved
server-side through kora_lib's permission gateway, so `kora_core.admin`, the bare
`group.admin` ace, and any Discord roles a server maps all satisfy it, and a
`god` cascades past an `admin` requirement.

```lua
Config.logout = {
    enabled = true,
    command = 'logout',
    minimumPermission = 'admin',
}
```

The command refuses while a character-select, spawn, or scene-studio session is
open — those own the routing bucket and camera, and dropping the character
under them would strand the client in a scene it cannot leave.

The command itself only calls kora_core's logout. Returning to character select
is driven by the replicated `kora_core:loggedIn` state that logout clears, not by
an event this resource sends, so **any** logout path lands back in selection —
an admin resource calling the core export, or a character delete that logs out
a live handle, behaves identically to `/logout`.

## Scene Studio

Admins and gods can open `/multicharscene`. The permission check is
server-side and cascading. The studio can create, load/duplicate, and edit
metadata, selectors, environment, character placement, local entities,
cameras, and timeline cues.

- Press **Tab** to switch between the themed inspector and freecam.
- Freecam uses kora_lib's shared camera lifecycle with mouse look, WASD, Q/E
  vertical movement, and Shift boost. Native instructional buttons show the
  live bindings while freecam is active.
- Placement and camera capture use crosshair raycasts and store relative
  coordinates.
- Timeline controls support cue editing, scrubbing, looping, and live preview.
- **Copy Config** and **Copy Registration** generate stable, sorted Lua with
  three-decimal coordinates through kora_lib's clipboard support.

The studio never writes resource files or a database. Paste the copied output
into configuration or another resource after reviewing it.

## One-screen select and arrival flight

With `Config.arrival.enabled = true` (the default) character and arrival point are
chosen on one screen: characters on the left, that character's arrival points on
the right, **Play** in the middle. Left/right and A/D change character, up/down
change arrival point, Enter plays. The character's own cinematic scene stays as
the backdrop; changing arrival point changes nothing in the world, so there is no
cooldown, no settle delay and no loading cover while choosing. With it disabled
the original **Continue** then spawn-carousel flow is used unchanged.

- The arrival list is fetched per character (`multichar:spawn:list`) on the same
  120 ms debounce as the scene preview. It is "Last Location" (its coordinates
  are only known after login), then `Config.spawns`, then owned properties from
  `qb-spawn:server:getOwnedHouses`. Coordinates and preview shots stay in Lua;
  the UI only receives `id`, `label`, `description` and `typeLoc`.
- **Play** sends `multichar:play { citizenid, locationId }`. Lua checks the
  character belongs to the list it showed and the id belongs to that character's
  list, then logs the character in with the same
  `qb-multicharacter:server:loadUserData` event Continue uses. The server's
  `qb-spawn:client:setupSpawns` and `openUI` answers start the flight instead of
  opening the picker. A server refusal, or a login that has not answered after
  20 s, releases the Play and shows an error.
- The flight is real script cameras (`SceneRuntime.flyToArrival`): **lift** out
  of the scene, **cruise** across while the destination streams, **descent**
  into the location's `preview` shot (or a camera behind and above the ped when
  it has none). The streaming focus only moves to the destination once the lift
  is done, so the scene stays loaded while rising. The scene's weather and clock
  are released before the descent so the player sees the real world. Timings and
  altitude come from `Config.spawnFlight`. **Space** shortens the travel
  (`Config.arrival.skippable`); the destination is still streamed.
- The arrival (`SceneRuntime.completeArrival`) places the ped at the point (plus
  `Config.arrival.zOffset`, default -0.08) while invisible and unfrozen, so it
  drops onto the ground before it is shown. The arrival coordinate is the ped's
  root, about a metre above the ground, so freezing it there would leave it
  hovering. It then fires `QBCore:Server:OnPlayerLoaded` (so the saved or starter
  outfit is applied unseen), waits `Config.arrival.settleMs`, plays the particle
  effect at the ped's feet, fades the ped in over `pedFadeMs` and blends the
  camera back to gameplay over `handbackMs`. HUD and controls stay off until it
  finishes, exactly as during select, and `kora_multichar:client:spawnComplete`
  fires at the end.
- The effect is `Config.arrival.ptfx` (`asset`, `effect`, `scale`, `zOffset`,
  `enabled`, `synced`, `syncRadius`). Its asset is requested when the flight
  starts, not when the ped arrives, so it is resident when needed; if it is not
  (or fails) the arrival loads it briefly on demand and then carries on without
  it. Choose the look in game.
- With `synced = true` (the default) players near the arrival see the effect
  too. The arriving client reports only the position
  (`kora_multichar:server:arrivalEffect`); the server checks the player is logged
  in, that the position is within 25 m of where it knows their ped is, and that
  they have not sent one in the last 5 s, then tells every player in the same
  routing bucket within `syncRadius` metres
  (`kora_multichar:client:arrivalEffect`) to play the effect named in the server's
  own config. A client can never choose the asset, effect or scale other
  players load. Each receiving client validates the event again and ignores it
  while it is on character select. This is a relay rather than the game's
  networked particle call so it does not depend on network scope. Set
  `synced = false` to keep it local to the arriving player.
- Where the ground under the arrival point can be found, the ped is placed at
  standing height above it, so there is no fall to wait for and the effect
  starts on the ground at once.
- If the flight cannot run (no camera, a stale flight, an error) the original
  fade-out, teleport, fade-in spawn is used, so a player is never left on the
  select screen.
- New characters take the same flight to `Config.defaultSpawn` after creation.
  Characters routed through `qb-apartments`, and the legacy brand-new-character
  picker, keep the spawn carousel.

## Spawn configuration

`Config.spawns` is an **ordered array**, each entry carrying its own `id`. It
still accepts nothing more than `{ id, coords, label }` and adds `description`
plus optional live-preview data:

```lua
Config.spawns = {
    { id = 'legion', coords = vector4(195.17, -933.77, 30.69, 144.0), label = 'Legion Square' },
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
    },
}

-- The first entry is also the new-character arrival point.
Config.defaultSpawn = Config.spawns[1].coords
```

The array replaces a table keyed by id. `pairs` has no defined iteration order,
so a keyed table gave the carousel a different running order on every client
and left "the first spawn location" — the thing `Config.defaultSpawn` and the
streaming fallback both reach for — meaning nothing in particular. Move an
entry to reorder the picker.

Without `preview`, a safe elevated camera is derived from the destination.
Future housing integrations can return coordinate-bearing owned houses through
the existing `qb-spawn:server:getOwnedHouses` callback and they will appear
automatically, sorted by label behind the configured spawns.

## Isolation and cleanup

Selection/spawn sessions use bucket `1100000 + source`; creator sessions use
`1200000 + source`. The previous bucket is restored through kora_core's bucket
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
'qb-multicharacter:server:GetServerLogs'  -- always {}
```

`/closeNUI` is registered (refused during a cinematic session). `qb-spawn:client:setupSpawns(cData, true, apps)`
builds the carousel from the qb-apartments location list; choosing one fires stock
`apartments:server:CreateApartment`. While `qb-apartments` is started, a returning player's
`setupSpawns(cData, false)` is first routed through `apartments:client:setupSpawnUI` (5s timeout back
to the normal picker); without it nothing is emitted.

kora_clothing protects preview appearance reads with kora_core ownership checks,
soft-delete filtering, sanitization, rate limiting, and a per-selection cache.
