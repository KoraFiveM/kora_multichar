-- Custom full-screen NUI: this resource owns its own frame (html/), so it
-- talks to it with the raw natives directly. QB.nui.send/registerCallback
-- would dispatch into qblib's own resource VM via the cross-resource export
-- call and so target QBLIB's frame, not this one -- QB.theme.tokens() is
-- still safe to call either way since it's pure Lua math with no NUI
-- natives involved.
--
-- Speaks the REAL legacy qb-multicharacter wire protocol directly (net
-- events + QB.callback names, verified against
-- github.com/qbcore-framework/qb-multicharacter) instead of qbcore's own
-- modern qbcore:server:*/qbcore:client:* pair, so any third-party resource
-- built against real QBCore keeps working against this one. NUI action/
-- callback names (multichar:*) are internal and unchanged -- RegisterNUICallback
-- is scoped to this resource's own shipped HTML, never cross-resource
-- observable, so matching real qb-multicharacter's NUI callback names
-- wouldn't buy any compat; the net events/QB.callback names are the actual
-- cross-resource surface, and those are matched exactly.

local lastCharacters = {}
local maxCharacters = 5

-- Suppress qbcore's built-in auto-select/auto-create flow
-- (qbcore/modules/multichar/client.lua) -- must run before its 500ms grace
-- window elapses, which this does trivially since it's top-level code that
-- runs the moment this resource starts. This is a real cross-resource export
-- call, not a `_G` flag -- every resource gets its own isolated Lua VM, so a
-- `_G` write here would never actually be visible to qbcore's own script.
-- Still required even though this file no longer speaks qbcore's own
-- qbcore:server:*/qbcore:client:* pair: qbcore's default flow re-arms itself
-- via TriggerServerEvent('qbcore:server:requestCharacters') on its own timer
-- regardless of what this resource does, unless claimed.
exports.qbcore:claimUI()

---Smallest slot in 1..maxCharacters not occupied by an existing character.
---@param characters table[]
---@return integer|nil
local function nextFreeSlot(characters)
    local taken = {}
    for _, character in ipairs(characters) do
        taken[character.cid] = true
    end
    for cid = 1, maxCharacters do
        if not taken[cid] then return cid end
    end
    return nil
end

local function closeUI()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'multichar:close' })
end

-- The point every "you're now in the world" path converges on: teleport,
-- tell the server the legacy way, drop the loading screen, close this UI.
local function finishAtDefaultSpawn()
    local ped = PlayerPedId()
    local spawn = Config.defaultSpawn
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, true)
    SetEntityHeading(ped, spawn.w)
    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.w, GetEntityModel(ped), false)
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(500)
    closeUI()
end

local function refreshCharacters()
    local characters = QB.callback.trigger('qb-multicharacter:server:setupCharacters') or {}
    maxCharacters = QB.callback.trigger('qb-multicharacter:server:GetNumberOfCharacters') or maxCharacters
    lastCharacters = characters

    -- The "shutdown the loading screen after all chars fetched" behavior --
    -- safe to call even if something else already shut it down (e.g. a bare
    -- server's spawnmanager on a previous connect). ShutdownLoadingScreen()
    -- alone only tears down the loadingscreen resource's NUI page; with
    -- loadscreen_manual_shutdown 'yes' (qb-loading/fxmanifest.lua) the
    -- client stays on a black/stuck screen until ShutdownLoadingScreenNui()
    -- and a fade-in are also fired.
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(500)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'multichar:show',
        data = { characters = characters, maxCharacters = maxCharacters },
    })
end

-- Real qb-multicharacter events

RegisterNetEvent('qb-multicharacter:client:chooseChar', refreshCharacters)

RegisterNetEvent('qb-multicharacter:client:closeNUI', closeUI)

RegisterNetEvent('qb-multicharacter:client:closeNUIdefault', finishAtDefaultSpawn)

RegisterNetEvent('qb-multicharacter:client:spawnLastLocation', function(coords, _cData)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    SetEntityHeading(ped, coords.w or coords.h or 0.0)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.w or coords.h or 0.0, GetEntityModel(ped), false)
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(500)
    closeUI()
end)

-- Local-only UX event (NOT part of the legacy wire protocol) -- qbcore's
-- compat (compat/server/qb-multicharacter.lua) fires this on a failed
-- select/create instead of silently doing nothing.
RegisterNetEvent('multichar:client:selectFailed', function(err)
    SendNUIMessage({ action = 'multichar:error', data = err or 'Something went wrong.' })
end)

-- NUI callbacks

RegisterNUICallback('multichar:getTheme', function(_, cb)
    cb(QB.theme.tokens())
end)

RegisterNUICallback('multichar:select', function(data, cb)
    TriggerServerEvent('qb-multicharacter:server:loadUserData', { citizenid = data.citizenid })
    cb({})
end)

RegisterNUICallback('multichar:create', function(data, cb)
    local cid = nextFreeSlot(lastCharacters)
    if not cid then
        SendNUIMessage({ action = 'multichar:error', data = 'You have reached the maximum number of characters.' })
        cb({})
        return
    end

    TriggerServerEvent('qb-multicharacter:server:createCharacter', {
        firstname = data.firstname,
        lastname = data.lastname,
        birthdate = '1990-01-01',
        gender = 0,
        nationality = 'USA',
        phone = tostring(math.random(1000000, 9999999)),
        cid = cid,
    })
    cb({})
end)

RegisterNUICallback('multichar:delete', function(data, cb)
    TriggerServerEvent('qb-multicharacter:server:deleteCharacter', data.citizenid)
    -- Real qb-multicharacter's own removeCharacter NUI callback just re-fires
    -- chooseChar locally to refresh the list; matched here.
    refreshCharacters()
    cb({})
end)

RegisterNUICallback('multichar:close', function(_, cb)
    SetNuiFocus(false, false)
    cb({})
end)

-- Kick off the flow once the session is up -- matches real qb-multicharacter's
-- own NetworkIsSessionStarted() gate (this used to be a flat
-- TriggerServerEvent('qbcore:server:requestCharacters') at file scope, which
-- ran before the network session existed).
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(0) end
    TriggerEvent('qb-multicharacter:client:chooseChar')
end)

-- Live-push path for a theme change while the UI is already open; the page
-- also pulls this once on mount via multichar:getTheme.
SendNUIMessage({ action = 'multichar:theme', data = QB.theme.tokens() })
