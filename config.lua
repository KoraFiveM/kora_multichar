-- Own config, self-contained -- matches real qb-spawn's convention of owning
-- its data rather than reading qbcore's shared registries. Named `Config.*`,
-- not `QB.Spawns` (real qb-spawn's global) -- `qblib`'s `@qblib/init.lua`
-- already owns the global `QB` as a live cross-resource proxy in this
-- codebase, so reusing that name here would shadow it. This has zero
-- backward-compat impact: Lua globals never cross resource VMs, so a third
-- party can only ever observe this resource through net events/callbacks,
-- never by reading its internal config table directly.

Config = {}

-- Where a brand-new character lands (real qb-multicharacter's
-- Config.DefaultSpawn, used by the closeNUIdefault path -- no apartments
-- module exists here, so every new character takes this route).
Config.defaultSpawn = vector4(-269.4, -955.3, 31.2, 205.8)

-- The spawn-picker's fixed location list, always offered alongside "last
-- location". `legion`/`pillbox` reuse qbcore/shared/locations.lua's
-- spawn_legion/spawn_pillbox coordinates re-expressed as vector4; the rest
-- are fresh defaults.
Config.spawns = {
    legion  = { coords = vector4(195.17, -933.77, 30.69, 144.0), label = 'Legion Square' },
    pillbox = { coords = vector4(307.7,  -595.5,  43.28, 90.0),  label = 'Pillbox Hill'   },
    sandy   = { coords = vector4(1839.7, 3672.8,  34.28, 210.0), label = 'Sandy Shores'   },
    paleto  = { coords = vector4(-108.4, 6431.5,  31.6,  227.6), label = 'Paleto Bay'     },
}
