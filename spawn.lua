local spawnLocations = {}
local spawnById = {}

local focusSeq, lastFocusAt = 0, 0

local function switchCooldownMs()
    return math.max(0, tonumber((Config.spawnSelect or {}).switchCooldownMs) or 0)
end

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

---`deferLast` is for the one-screen select, which lists a character's arrival
---points BEFORE they are logged in: their saved position is not known yet, so
---"Last Location" is listed without coordinates and filled in after login.
local function buildLocations(cData, houses, isNew, apartments, deferLast)
    spawnLocations, spawnById = {}, {}
    local current = isNew and Config.defaultSpawn or (cData and normalizeCoords(cData.position))
    if current and not apartments then
        addLocation({
            id = 'current', typeLoc = 'current', label = isNew and Kora.lang('Spawn.first_arrival') or Kora.lang('Spawn.last_location'),
            description = isNew and Kora.lang('Spawn.first_arrival_description') or Kora.lang('Spawn.last_location_description'),
            coords = current,
        })
    elseif deferLast and not isNew and not apartments then
        local deferred = {
            id = 'current', typeLoc = 'current', label = Kora.lang('Spawn.last_location'), deferred = true,
            description = Kora.lang('Spawn.last_location_description'),
        }
        spawnLocations[#spawnLocations + 1] = deferred
        spawnById[deferred.id] = deferred
    end
    for _, configured in ipairs(apartments and {} or Config.spawns) do
        addLocation({
            id = configured.id, typeLoc = 'normal', spawnloc = configured.id,
            label = configured.label or configured.id, description = configured.description,
            coords = configured.coords, preview = configured.preview,
        })
    end

    local owned = {}
    for key, house in pairs(type(houses) == 'table' and houses or {}) do
        local coords = normalizeCoords(house.coords or house.location or house)
        if coords then
            owned[#owned + 1] = {
                id = ('house:%s'):format(tostring(house.id or key)), typeLoc = 'house', spawnloc = house.id or key,
                label = house.label or house.name or Kora.lang('Spawn.owned_property'),
                description = Kora.lang('Spawn.owned_property_description'), coords = coords,
            }
        end
    end
    table.sort(owned, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    for _, house in ipairs(owned) do addLocation(house) end

    local starting = {}
    for key, apartment in pairs(type(apartments) == 'table' and apartments or {}) do
        local enter = type(apartment) == 'table' and type(apartment.coords) == 'table' and apartment.coords.enter
        local coords = normalizeCoords(enter or apartment)
        local name = tostring(type(apartment) == 'table' and apartment.name or key)
        if coords then
            starting[#starting + 1] = {
                id = ('apartment:%s'):format(name), typeLoc = 'apartment', apartmentType = name,
                label = apartment.label or name, description = Kora.lang('Spawn.new_apartment_description'), coords = coords,
            }
        end
    end
    table.sort(starting, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    for _, apartment in ipairs(starting) do addLocation(apartment) end
end

local openSpawnSelection
local apartmentsRouted, apartmentsToken = false, 0
local lastIsNew = false

local function publishLocations(cData, isNew, apartments)
    local houses = {}
    if not isNew then
        houses = Kora.callback.trigger('qb-spawn:server:getOwnedHouses', cData and cData.citizenid) or {}
    end
    buildLocations(cData, houses, isNew, apartments)
    if apartments and #spawnLocations == 0 then buildLocations(cData, houses, isNew) end
    lastIsNew = isNew
    send('multichar:spawn:locations', {
        locations = spawnLocations, isNew = isNew,
        previewBudgetMs = SceneRuntime.spawnPreviewBudgetMs(),
    })
end

local function apartmentsStarted()
    return GetResourceState('qb-apartments') == 'started'
end

-- One-screen select: the Play the player pressed, waiting for the server to log
-- them in. { citizenid, locationId, ready = true once the post-login list is built }
local pendingPlay

local PLAY_LOGIN_TIMEOUT_MS = 20000

---Called when the server refuses to load the chosen character.
function multicharPlayFailed()
    pendingPlay = nil
end

local function arrivalEnabled()
    return (Config.arrival or {}).enabled ~= false
end

---The arrival point to use: the chosen one, else the saved position, else the
---first configured spawn, so a pending Play always ends in a spawn.
---@param locationId string
---@return table|nil
local function resolveArrival(locationId)
    local chosen = spawnById[locationId]
    if chosen and chosen.coords then return chosen end
    return spawnById.current and spawnById.current.coords and spawnById.current
        or spawnById[(Config.spawns[1] or {}).id] or spawnLocations[1]
end

---Starts the arrival flight for a logged-in character.
---@param location table
local function beginArrival(location)
    local entered, err = Kora.callback.trigger('kora_multichar:server:enterMode', 'spawn')
    if not entered then
        -- No session to move out of: just spawn them rather than strand them.
        send('multichar:error', err or Kora.lang('Notify.arrival_flight_failed'))
        multicharFinishSpawn(location.coords, false)
        return
    end
    multicharSetClientMode('spawn', true)
    multicharArrive(location, false)
end

---What the one-screen select shows for a character: id, label and description
---only. Coordinates stay on this side.
local function summarise(list)
    local out = {}
    for _, location in ipairs(list) do
        out[#out + 1] = {
            id = location.id, label = location.label, description = location.description,
            typeLoc = location.typeLoc,
        }
    end
    return out
end

local function ownedHousesFor(citizenid)
    return Kora.callback.trigger('qb-spawn:server:getOwnedHouses', citizenid) or {}
end

RegisterNUICallback('multichar:spawn:list', function(data, cb)
    local citizenid = type(data) == 'table' and data.citizenid
    if not arrivalEnabled() or type(citizenid) ~= 'string' or not multicharHasCharacter(citizenid) then
        cb({ ok = false, locations = {} })
        return
    end
    buildLocations(nil, ownedHousesFor(citizenid), false, nil, true)
    cb({ ok = true, locations = summarise(spawnLocations) })
end)

RegisterNUICallback('multichar:play', function(data, cb)
    data = type(data) == 'table' and data or {}
    local citizenid, locationId = data.citizenid, data.locationId
    if not arrivalEnabled() or pendingPlay or type(locationId) ~= 'string' or not multicharHasCharacter(citizenid) then
        cb({ ok = false })
        return
    end
    -- Rebuilt now, from the character being logged in, so the id is checked
    -- against that character's own list and not whichever one was built last.
    buildLocations(nil, ownedHousesFor(citizenid), false, nil, true)
    if not spawnById[locationId] then
        send('multichar:error', Kora.lang('Notify.arrival_unavailable'))
        cb({ ok = false })
        return
    end
    local play = { citizenid = citizenid, locationId = locationId }
    pendingPlay = play
    SetTimeout(PLAY_LOGIN_TIMEOUT_MS, function()
        if pendingPlay == play then
            pendingPlay = nil
            send('multichar:error', Kora.lang('Notify.character_load_timeout'))
        end
    end)
    multicharLoadCharacter(citizenid)
    cb({ ok = true })
end)

RegisterNetEvent('qb-spawn:client:setupSpawns', function(cData, new, apps)
    if pendingPlay then
        if not new and not apartmentsStarted() then
            -- Logged in: rebuild the list with the real saved position so
            -- "Last Location" has coordinates, then wait for openUI.
            buildLocations(cData, ownedHousesFor(cData and cData.citizenid), false)
            lastIsNew = false
            pendingPlay.ready = true
            return
        end
        -- Apartment routing and brand-new characters keep the spawn picker.
        pendingPlay = nil
    end
    if new then
        apartmentsRouted = false
        publishLocations(cData, true, type(apps) == 'table' and apps or nil)
        return
    end
    if apartmentsStarted() and not apartmentsRouted then
        apartmentsRouted = true
        apartmentsToken = apartmentsToken + 1
        local token = apartmentsToken
        TriggerEvent('apartments:client:setupSpawnUI', cData)
        SetTimeout(5000, function()
            if apartmentsRouted and apartmentsToken == token then
                apartmentsRouted = false
                publishLocations(cData, false)
                openSpawnSelection(false)
            end
        end)
        return
    end
    apartmentsRouted = false
    publishLocations(cData, false)
end)

openSpawnSelection = function(isNew)
    local entered, err = Kora.callback.trigger('kora_multichar:server:enterMode', 'spawn')
    if not entered then
        send('multichar:error', err or Kora.lang('Notify.spawn_selection_failed'))
        return
    end
    multicharSetClientMode('spawn', true)
    SetNuiFocus(true, true)
    send('multichar:spawn:show', {
        visible = true, isNew = isNew == true,
        previewBudgetMs = SceneRuntime.spawnPreviewBudgetMs(),
        switchCooldownMs = switchCooldownMs(),
        settleMs = math.max(0, tonumber((Config.spawnSelect or {}).settleMs) or 0),
        lockWhileMoving = (Config.spawnSelect or {}).lockWhileMoving ~= false,
        hints = (Config.spawnSelect or {}).hints,
    })
    return true
end

RegisterNetEvent('qb-spawn:client:openUI', function(value)
    if value ~= true then return end
    if pendingPlay then
        -- setupSpawns may still be building the list when this arrives.
        local play = pendingPlay
        local deadline = GetGameTimer() + 8000
        while pendingPlay == play and not play.ready and GetGameTimer() < deadline do Wait(0) end
        if pendingPlay == play and play.ready then
            pendingPlay = nil
            local location = resolveArrival(play.locationId)
            if location and location.coords then
                beginArrival(location)
                return
            end
        end
        pendingPlay = nil
    end
    if apartmentsRouted then return end
    openSpawnSelection(lastIsNew)
end)

RegisterNUICallback('multichar:spawn:focus', function(data, cb)
    local location = spawnById[type(data) == 'table' and data.id or nil]
    local ok, streamed, reason = false, false, 'that location is not on the list'
    focusSeq = focusSeq + 1
    local ticket = focusSeq
    local remaining = lastFocusAt + switchCooldownMs() - GetGameTimer()
    if location and remaining > 0 then
        Wait(remaining)
        if ticket ~= focusSeq then
            cb({ ok = false, streamed = false, reason = SceneRuntime.PREVIEW_SUPERSEDED })
            return
        end
    end
    lastFocusAt = GetGameTimer()
    if location then ok, streamed, reason = SceneRuntime.previewSpawn(location) end
    cb({ ok = ok, streamed = streamed, reason = reason })
end)

RegisterNUICallback('multichar:spawn:choose', function(data, cb)
    local location = spawnById[type(data) == 'table' and data.id or nil]
    if not location then cb({ ok = false }); return end
    if location.typeLoc == 'apartment' and apartmentsStarted() then
        TriggerServerEvent('apartments:server:CreateApartment', location.apartmentType, location.label, true)
        multicharFinishSpawn(location.coords, true)
    else
        multicharFinishSpawn(location.coords, lastIsNew)
    end
    cb({ ok = true })
end)

RegisterNUICallback('multichar:spawn:exit', function(_, cb)
    send('multichar:error', Kora.lang('Notify.choose_spawn'))
    cb({ ok = false, mandatory = true })
end)
