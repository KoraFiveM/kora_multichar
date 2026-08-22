-- The merged qb-spawn client half. Kept in its own file, talking to the rest
-- of this resource ONLY via the real cross-resource qb-spawn:client:* net
-- events and qb-spawn:server:* callback -- the same way the two real,
-- separate resources talk to each other -- so this stays a faithful,
-- decoupled compat surface rather than a hidden internal shortcut.
--
-- This is also the only place in the whole codebase that ever moves the
-- player's ped after character select (confirmed at design time: no
-- spawnmanager integration exists anywhere). Real qb-spawn/qb-multicharacter
-- don't use spawnmanager either -- they hand-roll SetEntityCoords /
-- NetworkResurrectLocalPlayer / fade calls directly, matched here.

local lastCData = nil

local function finishSpawn(coords)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    SetEntityHeading(ped, coords.w or coords.h or 0.0)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.w or coords.h or 0.0, GetEntityModel(ped), false)
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')

    -- Same 3-call sequence as client.lua's character-list shutdown -- safe to
    -- call again here (loadscreen_manual_shutdown 'yes' means only the FIRST
    -- call actually does anything; a repeat is a harmless no-op), and this is
    -- genuinely the point at which the player is finally in the world.
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(500)

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'multichar:spawn:show', data = { visible = false } })
end

RegisterNetEvent('qb-spawn:client:openUI', function(value)
    SendNUIMessage({ action = 'multichar:spawn:show', data = { visible = value } })
    SetNuiFocus(value, value)
end)

RegisterNetEvent('qb-spawn:client:setupSpawns', function(cData, new, _apps)
    -- `new`/`apps` (apartments path) never fire here -- qbcore's compat
    -- (compat/server/qb-multicharacter.lua) never takes that branch, since no
    -- apartments module exists in this codebase.
    if new then return end

    lastCData = cData
    local houses = QB.callback.trigger('qb-spawn:server:getOwnedHouses', cData and cData.citizenid) or {}
    SendNUIMessage({
        action = 'multichar:spawn:locations',
        data = { locations = Config.spawns, houses = houses, isNew = false },
    })
end)

RegisterNUICallback('multichar:spawn:exit', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'multichar:spawn:show', data = { visible = false } })
    cb({})
end)

RegisterNUICallback('multichar:spawn:choose', function(data, cb)
    if data.typeLoc == 'current' and lastCData and lastCData.position then
        finishSpawn(lastCData.position)
    elseif data.typeLoc == 'normal' and Config.spawns[data.spawnloc] then
        finishSpawn(Config.spawns[data.spawnloc].coords)
    end
    -- 'house'/'appartment': unreachable -- qb-spawn:server:getOwnedHouses
    -- (qbcore/compat/server/qb-spawn.lua) always answers {}, so the NUI never
    -- offers them; a stray call is a defensive no-op, not an error.
    cb({})
end)
