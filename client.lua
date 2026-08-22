-- Custom full-screen NUI: this resource owns its own frame (html/), so it
-- talks to it with the raw natives directly. QB.nui.send/registerCallback
-- would dispatch into qblib's own resource VM via the cross-resource export
-- call and so target QBLIB's frame, not this one -- QB.theme.tokens() is
-- still safe to call either way since it's pure Lua math with no NUI
-- natives involved.

-- Mirrors qbcore's own Config.identity.maxCharacters (qbcore/config.lua) --
-- multichar has no direct read access to qbcore's internal Config table, so
-- this is kept in sync by hand. Update alongside that value if it changes.
local MAX_CHARACTERS = 5

local lastCharacters = {}

-- Suppress qbcore's built-in auto-select/auto-create flow
-- (qbcore/modules/multichar/client.lua) -- must run before its 500ms grace
-- window elapses, which this does trivially since it's top-level code that
-- runs the moment this resource starts. This is a real cross-resource export
-- call, not a `_G` flag -- every resource gets its own isolated Lua VM, so a
-- `_G` write here would never actually be visible to qbcore's own script
-- (this bugged silently: qbcore kept auto-selecting slot 1 a moment after
-- connect regardless, so every later selection from this UI failed with
-- "source already logged in").
exports.qbcore:claimUI()

---Smallest slot in 1..MAX_CHARACTERS not occupied by an existing character.
---@param characters table[]
---@return integer|nil
local function nextFreeSlot(characters)
    local taken = {}
    for _, character in ipairs(characters) do
        taken[character.cid] = true
    end
    for cid = 1, MAX_CHARACTERS do
        if not taken[cid] then return cid end
    end
    return nil
end

local function closeUI()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'multichar:close' })
end

RegisterNetEvent('qbcore:client:receiveCharacters', function(characters)
    lastCharacters = characters or {}

    -- The "shutdown the loading screen after all chars fetched" behavior --
    -- safe to call even if something else already shut it down (e.g. a bare
    -- server's spawnmanager on a previous connect).
    ShutdownLoadingScreen()

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'multichar:show',
        data = { characters = lastCharacters, maxCharacters = MAX_CHARACTERS },
    })
end)

RegisterNetEvent('qbcore:client:characterSelected', function(ok, err)
    if ok then
        closeUI()
        return
    end

    -- A resource restart (or a stray double-select) while already spawned
    -- re-requests the character list and can hit this; the player is already
    -- in game and fine, so just close instead of surfacing a scary error.
    if err == 'source already logged in' then
        closeUI()
        return
    end

    SendNUIMessage({ action = 'multichar:error', data = err or 'Something went wrong.' })
end)

RegisterNUICallback('multichar:getTheme', function(_, cb)
    cb(QB.theme.tokens())
end)

RegisterNUICallback('multichar:select', function(data, cb)
    TriggerServerEvent('qbcore:server:selectCharacter', data.citizenid)
    cb({})
end)

RegisterNUICallback('multichar:create', function(data, cb)
    local cid = nextFreeSlot(lastCharacters)
    if not cid then
        SendNUIMessage({ action = 'multichar:error', data = 'You have reached the maximum number of characters.' })
        cb({})
        return
    end

    TriggerServerEvent('qbcore:server:createCharacter', {
        firstname = data.firstname,
        lastname = data.lastname,
        birthdate = '1990-01-01',
        gender = 0,
        nationality = 'USA',
        phone = tostring(math.random(1000000, 9999999)),
    }, cid)
    cb({})
end)

RegisterNUICallback('multichar:delete', function(data, cb)
    TriggerServerEvent('qbcore:server:deleteCharacter', data.citizenid)
    cb({})
end)

RegisterNUICallback('multichar:close', function(_, cb)
    SetNuiFocus(false, false)
    cb({})
end)

-- Kick off the flow -- the moment this resource starts is the equivalent
-- point qbcore's own (now-suppressed) default flow would have fired at.
TriggerServerEvent('qbcore:server:requestCharacters')

-- Live-push path for a theme change while the UI is already open; the page
-- also pulls this once on mount via multichar:getTheme.
SendNUIMessage({ action = 'multichar:theme', data = QB.theme.tokens() })
