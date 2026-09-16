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

-- Built in a fixed order rather than sorted afterwards: last location first,
-- then Config.spawns exactly as the server owner declared it, then any owned
-- property. Both of the sources this reads used to be walked with `pairs`, so
-- the carousel came out in a different order on every client and nothing could
-- refer to "the first location" and mean it.
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
    for _, configured in ipairs(Config.spawns) do
        addLocation({
            id = configured.id, typeLoc = 'normal', spawnloc = configured.id,
            label = configured.label or configured.id, description = configured.description,
            coords = configured.coords, preview = configured.preview,
        })
    end

    -- qb-houses hands these over keyed by house id, which carries no order of
    -- its own -- sorted by label so the tail of the list is stable too.
    local owned = {}
    for key, house in pairs(type(houses) == 'table' and houses or {}) do
        local coords = normalizeCoords(house.coords or house.location or house)
        if coords then
            owned[#owned + 1] = {
                id = ('house:%s'):format(tostring(house.id or key)), typeLoc = 'house', spawnloc = house.id or key,
                label = house.label or house.name or 'Owned Property',
                description = 'Spawn at your owned property.', coords = coords,
            }
        end
    end
    table.sort(owned, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    for _, house in ipairs(owned) do addLocation(house) end
end

RegisterNetEvent('qb-spawn:client:setupSpawns', function(cData, new, _apps)
    if new then return end
    local houses = QB.callback.trigger('qb-spawn:server:getOwnedHouses', cData and cData.citizenid) or {}
    buildLocations(cData, houses, false)
    send('multichar:spawn:locations', {
        locations = spawnLocations, isNew = false,
        previewBudgetMs = SceneRuntime.spawnPreviewBudgetMs(),
    })
end)

local function openSpawnSelection(isNew)
    local entered, err = QB.callback.trigger('qbmultichar:server:enterMode', 'spawn')
    if not entered then
        send('multichar:error', err or 'Could not open spawn selection.')
        return
    end
    multicharSetClientMode('spawn', true)
    SetNuiFocus(true, true)
    -- The NUI races a timeout against every focus callback. It derives that
    -- timeout from this figure instead of carrying its own copy of the flight
    -- and streaming budgets, which is how it ended up timing out at 15s
    -- against a preview allowed to take five times as long.
    send('multichar:spawn:show', {
        visible = true, isNew = isNew == true,
        previewBudgetMs = SceneRuntime.spawnPreviewBudgetMs(),
    })
    return true
end

RegisterNetEvent('qb-spawn:client:openUI', function(value)
    if value == true then openSpawnSelection(false) end
end)

-- `reason` is what keeps the selector quiet while a player clicks through the
-- list: an abandoned preview reports SceneRuntime.PREVIEW_SUPERSEDED, which
-- the NUI treats as a non-event rather than a failed arrival.
RegisterNUICallback('multichar:spawn:focus', function(data, cb)
    local location = spawnById[type(data) == 'table' and data.id or nil]
    local ok, streamed, reason = false, false, 'that location is not on the list'
    if location then ok, streamed, reason = SceneRuntime.previewSpawn(location) end
    cb({ ok = ok, streamed = streamed, reason = reason })
end)

RegisterNUICallback('multichar:spawn:choose', function(data, cb)
    local location = spawnById[type(data) == 'table' and data.id or nil]
    if not location then cb({ ok = false }); return end
    -- House spawning becomes reachable automatically when qb-houses returns
    -- coordinates. This merged resource has no house-interior handoff, so the
    -- safe compatible behavior is to land at those authoritative coordinates.
    multicharFinishSpawn(location.coords)
    cb({ ok = true })
end)

RegisterNUICallback('multichar:spawn:exit', function(_, cb)
    -- Once qbcore has adopted a character there is no safe "back" operation;
    -- force an explicit destination instead of stranding a hidden live player.
    send('multichar:error', 'Choose a spawn location to continue.')
    cb({ ok = false, mandatory = true })
end)
