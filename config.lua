-- Own config, self-contained -- matches real qb-spawn's convention of owning
-- its data rather than reading kora_core's shared registries. Named `Config.*`,
-- not `QB.Spawns` (real qb-spawn's global) -- `kora_lib`'s `@kora_lib/init.lua`
-- already owns the global `QB` as a live cross-resource proxy in this
-- codebase, so reusing that name here would shadow it. This has zero
-- backward-compat impact: Lua globals never cross resource VMs, so a third
-- party can only ever observe this resource through net events/callbacks,
-- never by reading its internal config table directly.

Config = {}

Config.buckets = {
    selectionBase = 1100000,
    creatorBase = 1200000,
}

Config.sceneLimits = {
    maxScenes = 64,
    maxPeds = 8,
    maxVehicles = 6,
    maxProps = 24,
    maxCameras = 8,
    maxCues = 64,
    maxTimelineMs = 120000,
    -- Asset loads (models, anim dicts, particle assets). These are hard
    -- requirements -- a scene without its character model has nothing to show
    -- -- so the budget is generous: a cold client on a slow disk can sit well
    -- past ten seconds on its first request of the session.
    streamTimeoutMs = 20000,
    -- World streaming. A CEILING, not a target: the wait ends as soon as
    -- collision has loaded around the ped parked at the destination, which on a
    -- warm client is a second or two. Expiring shows the scene anyway rather
    -- than failing the preview -- the ped is there and the streamer is still
    -- working, so the last of the map pops in behind the camera.
    --
    -- This was 30s, from when the preview waited on a load scene with the ped
    -- still on the far side of the map: a signal that regularly never arrived,
    -- so the budget had to be long enough to look like patience rather than a
    -- hang. See streamWorld in scene.lua.
    worldStreamTimeoutMs = 8000,
}

-- Cinematic travel between spawn previews. The camera lifts away from the
-- current location, cruises above the world while the destination streams,
-- then dives along the destination shot's approach vector. Travel time is
-- distance-scaled and clamped so nearby choices do not feel sluggish while
-- cross-map flights remain watchable.
Config.spawnFlight = {
    liftHeight = 130.0,
    minAltitude = 180.0,
    maxAltitude = 420.0,
    liftDurationMs = 900,
    descentDurationMs = 1450,
    minTravelDurationMs = 1400,
    maxTravelDurationMs = 4200,
    unitsPerSecond = 650.0,
}

Config.defaultScene = 'civilian'

-- Custom static scenes may be added here. scenes.lua merges the six bundled
-- defaults without overwriting an explicitly configured id.
Config.scenes = {}

-- Staff logout. `/logout` drops the character but keeps the connection, which
-- is what real qb-multicharacter's own admin-only logout command does. The
-- level is checked through kora_lib's permission gateway, so the same ace/Discord
-- grants that reach every other staff tool on the server reach this too.
Config.logout = {
    enabled = true,
    command = 'logout',
    minimumPermission = 'admin',
}

Config.creator = {
    enabled = true,
    command = 'multicharscene',
    minimumPermission = 'admin',
    moveSpeed = 6.0,
    fastMultiplier = 3.0,
    lookSensitivity = 5.0,
    placementDistance = 8.0,
}

-- The spawn-picker's fixed location list, always offered alongside "last
-- location". `legion`/`pillbox` reuse kora_core/shared/locations.lua's
-- spawn_legion/spawn_pillbox coordinates re-expressed as vector4; the rest
-- are fresh defaults.
--
-- An ORDERED array whose entries carry their own `id`, not a table keyed by
-- id: `pairs` has no defined iteration order, so a keyed table handed the
-- carousel a different running order on each client and left "the first spawn
-- location" meaning nothing in particular. Move a block to reorder the picker.
Config.spawns = {
    {
        id = 'legion',
        coords = vector4(195.17, -933.77, 30.69, 144.0), label = 'Legion Square',
        description = 'The centre of Los Santos, close to shops, transit, and city life.',
        preview = { camera = vector3(219.0, -914.0, 45.0), lookAt = vector3(195.17, -933.77, 30.69) },
    },
    {
        id = 'pillbox',
        coords = vector4(307.7, -595.5, 43.28, 90.0), label = 'Pillbox Hill',
        description = 'Arrive beside Pillbox Hill Medical Center in central Los Santos.',
        preview = { camera = vector3(331.0, -578.0, 58.0), lookAt = vector3(307.7, -595.5, 43.28) },
    },
    {
        id = 'sandy',
        coords = vector4(1839.7, 3672.8, 34.28, 210.0), label = 'Sandy Shores',
        description = 'A quieter start in Blaine County near the airfield and medical center.',
        preview = { camera = vector3(1814.0, 3688.0, 50.0), lookAt = vector3(1839.7, 3672.8, 34.28) },
    },
    {
        id = 'paleto',
        coords = vector4(-108.4, 6431.5, 31.6, 227.6), label = 'Paleto Bay',
        description = 'Begin on the north coast among Paleto Bay businesses and services.',
        preview = { camera = vector3(-85.0, 6407.0, 49.0), lookAt = vector3(-108.4, 6431.5, 31.6) },
    },
}

-- Where a brand-new character lands (real qb-multicharacter's
-- Config.DefaultSpawn, used by the closeNUIdefault path). New characters
-- spawn here directly; they never enter the live-preview spawn selector.
--
-- Deliberately the FIRST entry of Config.spawns rather than a fifth set of
-- coordinates nobody can see in the picker: "the first location" and "where a
-- new character wakes up" are the same decision, so promoting an entry to the
-- top of that list moves both. Its `coords` are shared by reference, which is
-- safe -- nothing here mutates a spawn's coordinates.
Config.defaultSpawn = Config.spawns[1].coords
