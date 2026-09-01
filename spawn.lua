-- Live-location spawn carousel. The character is already adopted by qbcore at
-- this point but remains hidden in qbmultichar's selection bucket until a
-- destination is confirmed.

local spawnLocations = {}
local spawnById = {}

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function addLocation(location)
    if not location or not location.id or not location.coords then return end
    spawnLocations[#spawnLocations + 1] = location
    spawnById[location.id] = location
end

local function normalizeCoords(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then return nil end
    if not value.x or not value.y or not value.z then return nil end
    return vector4(value.x + 0.0, value.y + 0.0, value.z + 0.0, value.w or value.h or 0.0)
end

local function buildLocations(cData, houses, isNew)
    spawnLocations, spawnById = {}, {}
    local current = isNew and Config.defaultSpawn or (cData and normalizeCoords(cData.position))
    if current then
        addLocation({
            id = 'current', typeLoc = 'current', label = isNew and 'First Arrival' or 'Last Location',
            description = isNew and 'Begin your new story at the city welcome point.' or 'Return to the exact place this character was last seen.',
            coords = current,
        })
    end
    for id, configured in pairs(Config.spawns) do
        addLocation({
            id = id, typeLoc = 'normal', spawnloc = id,
            label = configured.label or id, description = configured.description,
            coords = configured.coords, preview = configured.preview,
        })
    end
    for key, house in pairs(type(houses) == 'table' and houses or {}) do
        local coords = normalizeCoords(house.coords or house.location or house)
        if coords then
            addLocation({
                id = ('house:%s'):format(tostring(house.id or key)), typeLoc = 'house', spawnloc = house.id or key,
                label = house.label or house.name or 'Owned Property',
                description = 'Spawn at your owned property.', coords = coords,
            })
        end
    end
    table.sort(spawnLocations, function(a, b)
        if a.id == 'current' then return true end
        if b.id == 'current' then return false end
        return a.label < b.label
    end)
end

RegisterNetEvent('qb-spawn:client:setupSpawns', function(cData, new, _apps)
    if new then return end
    local houses = QB.callback.trigger('qb-spawn:server:getOwnedHouses', cData and cData.citizenid) or {}
    buildLocations(cData, houses, false)
    send('multichar:spawn:locations', { locations = spawnLocations, isNew = false })
end)

local function openSpawnSelection(isNew)
    local entered, err = QB.callback.trigger('qbmultichar:server:enterMode', 'spawn')
    if not entered then
        send('multichar:error', err or 'Could not open spawn selection.')
        return
    end
    MulticharSetClientMode('spawn', true)
    SetNuiFocus(true, true)
    send('multichar:spawn:show', { visible = true, isNew = isNew == true })
    return true
end

RegisterNetEvent('qb-spawn:client:openUI', function(value)
    if value == true then openSpawnSelection(false) end
end)

function MulticharOpenNewSpawn()
    buildLocations(nil, nil, true)
    send('multichar:spawn:locations', { locations = spawnLocations, isNew = true })
    return openSpawnSelection(true)
end

RegisterNUICallback('multichar:spawn:focus', function(data, cb)
    local location = spawnById[type(data) == 'table' and data.id or nil]
    local ok, streamed = false, false
    if location then ok, streamed = SceneRuntime.previewSpawn(location) end
    cb({ ok = ok, streamed = streamed })
end)

RegisterNUICallback('multichar:spawn:choose', function(data, cb)
    local location = spawnById[type(data) == 'table' and data.id or nil]
    if not location then cb({ ok = false }); return end
    -- House spawning becomes reachable automatically when qb-houses returns
    -- coordinates. This merged resource has no house-interior handoff, so the
    -- safe compatible behavior is to land at those authoritative coordinates.
    MulticharFinishSpawn(location.coords)
    cb({ ok = true })
end)

RegisterNUICallback('multichar:spawn:exit', function(_, cb)
    -- Once qbcore has adopted a character there is no safe "back" operation;
    -- force an explicit destination instead of stranding a hidden live player.
    send('multichar:error', 'Choose a spawn location to continue.')
    cb({ ok = false, mandatory = true })
end)
