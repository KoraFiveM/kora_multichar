---
layout: default
title: qbmultichar
---

Custom full-screen character-selection and spawn-selection UI for
[qbcore](https://qbcore2.github.io/qbcore/). qbcore itself ships no NUI for
this — it deliberately doesn't `provide 'qb-multicharacter'`, so it never
silently breaks a real UI resource a server wants to keep. This resource fully
implements both legacy UIs and so claims both names: `provide
'qb-multicharacter'` and `provide 'qb-spawn'`. It speaks the real legacy
`qb-multicharacter`/`qb-spawn` wire protocol (net events + `QB.callback`
names) rather than qbcore's modern `qbcore:server:*`/`qbcore:client:*` pair,
so any third-party resource built against real QBCore keeps working against
it unmodified.

## Requirements

- [qblib](https://qbcore2.github.io/qblib/)
- [qbcore](https://qbcore2.github.io/qbcore/)

## Installation

`server.cfg`, in this order:
```
ensure qbsql
ensure qblib
ensure qbcore
ensure qbmultichar
```
No config needed beyond `config.lua`'s defaults — see Config highlights below.

## Usage examples

### How it claims the UI on connect
```lua
-- client.lua, top-level: runs before qbcore's own auto-select/auto-create
-- flow (500ms grace window) can arm, suppressing it for this session.
exports.qbcore:claimUI()
```
qbcore's compat/server layer maps the legacy events below onto its modern
`getCharacters`/`selectCharacter`/`deleteCharacter` funnel internally, so this
resource never has to call those exports directly — it only needs
`claimUI()` to tell qbcore a real UI has taken over.

### Fetching and rendering the character list
```lua
-- client.lua
local function refreshCharacters()
    local characters = QB.callback.trigger('qb-multicharacter:server:setupCharacters') or {}
    maxCharacters = QB.callback.trigger('qb-multicharacter:server:GetNumberOfCharacters') or maxCharacters

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'multichar:show',
        data = { characters = characters, maxCharacters = maxCharacters },
    })
end

RegisterNetEvent('qb-multicharacter:client:chooseChar', refreshCharacters)
```

### Selecting, creating, and deleting a character from the NUI
```lua
-- client.lua NUI callbacks, called from html/app.js via fetchNui(...)
RegisterNUICallback('multichar:select', function(data, cb)
    TriggerServerEvent('qb-multicharacter:server:loadUserData', { citizenid = data.citizenid })
    cb({})
end)

RegisterNUICallback('multichar:create', function(data, cb)
    TriggerServerEvent('qb-multicharacter:server:createCharacter', {
        firstname = data.firstname,
        lastname = data.lastname,
        birthdate = '1990-01-01',
        gender = 0,
        nationality = 'USA',
        phone = tostring(math.random(1000000, 9999999)),
    })
    cb({})
end)

RegisterNUICallback('multichar:delete', function(data, cb)
    local deleted, err = QB.callback.trigger('qb-multicharacter:server:deleteCharacter', data.citizenid)
    if not deleted then
        SendNUIMessage({ action = 'multichar:error', data = err or 'Could not delete that character.' })
        cb({ ok = false })
        return
    end
    refreshCharacters()
    cb({ ok = true })
end)
```

### Spawn selection after a character loads
```lua
-- spawn.lua
RegisterNetEvent('qb-spawn:client:setupSpawns', function(cData, new, _apps)
    if new then return end
    local houses = QB.callback.trigger('qb-spawn:server:getOwnedHouses', cData and cData.citizenid) or {}
    SendNUIMessage({
        action = 'multichar:spawn:locations',
        data = { locations = Config.spawns, houses = houses, isNew = false },
    })
end)

RegisterNUICallback('multichar:spawn:choose', function(data, cb)
    -- data.typeLoc is 'current' (last location) or 'normal' (a Config.spawns key)
    cb({})
end)
```

### Customizing the theme the NUI pulls on mount
```lua
-- Anywhere after `@qblib/init.lua` -- html/app.js requests this once via
-- fetchNui('multichar:getTheme') and applies it before render.
RegisterNUICallback('multichar:getTheme', function(_, cb)
    cb(QB.theme.tokens())
end)
```
To restyle the screen itself, edit `html/style.css`/`html/app.js` directly —
`html/index.html` is the only page listed in `fxmanifest.lua`'s `files {}`, so
any new asset needs adding there too.

## API reference

This resource exposes no exports of its own — its whole surface is the real
legacy `qb-multicharacter`/`qb-spawn` wire protocol, driven client-side only
(no `server.lua` in this resource; qbcore's own compat layer answers the
callbacks and fires the events below).

### Net events this resource listens for
```lua
'qb-multicharacter:client:chooseChar'        -- (re)fetch and show the character list
'qb-multicharacter:client:closeNUI'          -- close the UI, no spawn
'qb-multicharacter:client:closeNUIdefault'   -- close and spawn at Config.defaultSpawn
'qb-multicharacter:client:spawnLastLocation' -- close and spawn at a given coords
'multichar:client:selectFailed'              -- show an error toast on a failed select/create
'qb-spawn:client:openUI'                     -- show/hide the spawn-picker stage
'qb-spawn:client:setupSpawns'                -- populate spawn locations + owned houses
```

### Net events / callbacks this resource fires
```lua
TriggerServerEvent('qb-multicharacter:server:loadUserData', { citizenid })
TriggerServerEvent('qb-multicharacter:server:createCharacter', { firstname, lastname, birthdate, gender, nationality, phone })
QB.callback.trigger('qb-multicharacter:server:deleteCharacter', citizenid)
QB.callback.trigger('qb-multicharacter:server:setupCharacters')
QB.callback.trigger('qb-multicharacter:server:GetNumberOfCharacters')
QB.callback.trigger('qb-spawn:server:getOwnedHouses', citizenid)
TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
```

### NUI callbacks (`RegisterNUICallback`, called from `html/app.js`)
```lua
'multichar:getTheme'    'multichar:select'      'multichar:create'
'multichar:delete'      'multichar:close'       'multichar:spawn:exit'
'multichar:spawn:choose'
```

### NUI messages (`SendNUIMessage`, handled in `html/app.js`)
```lua
'multichar:show'      'multichar:close'          'multichar:error'
'multichar:theme'      'multichar:spawn:show'    'multichar:spawn:locations'
```

## Config highlights (`config.lua`)

`Config.defaultSpawn` (vector4 landing point for a brand-new character —
qbcore's `closeNUIdefault` path), `Config.spawns` (the fixed spawn-picker
location list: `legion`, `pillbox`, `sandy`, `paleto`, each `{ coords, label }`).
Character-slot cap comes from qbcore's own `Config.identity.maxCharacters`
(overridable per-license via `exports.qbcore:setMaxCharacters`), not from this
resource — `maxCharacters` here is only a client-side cache refreshed on every
list request.

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [qblib](https://qbcore2.github.io/qblib/) — shared helper library
- [qbsql](https://qbcore2.github.io/qbsql/) — database driver
- [qbcore](https://qbcore2.github.io/qbcore/) — framework core
- [qbinventory](https://qbcore2.github.io/qbinventory/) — headless inventory
- [qbloading](https://qbcore2.github.io/qbloading/) — loading screen
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
