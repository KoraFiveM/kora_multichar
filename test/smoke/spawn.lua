-- Spawn selector: the ordered location list and the preview budget the NUI
-- derives its timeout from. Both are things a `pairs` loop or a hardcoded
-- constant used to decide for us -- iteration order that differed per client,
-- and a 15s NUI timeout racing a preview allowed to take five times that.
local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local root = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')

local function vector(x, y, z, w)
    local result = { x = x, y = y, z = z }
    if w ~= nil then result.w = w end
    return result
end
_G.vector3 = function(x, y, z) return vector(x, y, z) end
_G.vector4 = function(x, y, z, w) return vector(x, y, z, w) end

dofile(root .. 'config.lua')

-- scene.lua's only top-level statement is its resource-stop handler; every
-- native it touches lives inside a function, so the runtime loads under plain
-- Lua and spawnPreviewBudgetMs can be called for real rather than pattern-
-- matched out of the source.
_G.AddEventHandler = function() end
dofile(root .. 'scene.lua')

-- spawn.lua registers handlers at load; capture them so the location list can
-- be built the way the game builds it, through the real net event.
local netHandlers, nuiMessages = {}, {}
_G.RegisterNetEvent = function(name, handler) netHandlers[name] = handler end
_G.RegisterNUICallback = function() end
_G.SendNUIMessage = function(payload) nuiMessages[#nuiMessages + 1] = payload end
local ownedHouses = {}
_G.GetResourceState = function() return 'missing' end
_G.Kora = { callback = { trigger = function() return ownedHouses end } }
dofile(root .. 'spawn.lua')

---@return table locations, table payload
local function buildList(position)
    nuiMessages = {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345', position = position }, false, {})
    local payload = nuiMessages[#nuiMessages]
    H.truthy(payload and payload.action == 'multichar:spawn:locations', 'setupSpawns must publish the location list')
    return payload.data.locations, payload.data
end

------------------------------------------------------------------------------
-- Ordered list
------------------------------------------------------------------------------

H.test('Config.spawns is an ordered array and every entry carries its own id', function()
    H.equal(#Config.spawns, 4, 'shipped spawn count')
    local seen = {}
    for index, entry in ipairs(Config.spawns) do
        H.truthy(type(entry.id) == 'string' and entry.id ~= '', ('entry %d needs an id'):format(index))
        H.falsy(seen[entry.id], ('duplicate spawn id %s'):format(tostring(entry.id)))
        seen[entry.id] = true
        H.truthy(entry.coords and entry.label, ('entry %s needs coords and a label'):format(entry.id))
    end
    -- A keyed table would leave `next(Config.spawns)` as the only notion of
    -- "first", and that is not stable across clients or restarts.
    H.equal(Config.spawns[1].id, 'legion', 'the first ordered entry')
end)

H.test('Config.defaultSpawn IS the first ordered entry, not a fifth hidden location', function()
    H.equal(Config.defaultSpawn, Config.spawns[1].coords,
        'a new character must land at the location the picker offers first')
end)

H.test('the published list is last location, then Config.spawns in declared order', function()
    local locations = buildList(vector4(1.0, 2.0, 3.0, 4.0))

    H.equal(locations[1].id, 'current', 'last location leads the list')
    for index, entry in ipairs(Config.spawns) do
        H.equal(locations[index + 1].id, entry.id, ('configured entry %d keeps its declared position'):format(index))
        H.equal(locations[index + 1].typeLoc, 'normal', 'configured entries stay normal spawns')
    end
    H.equal(#locations, #Config.spawns + 1, 'no extra locations')
end)

H.test('the same character rebuilt repeatedly always gets the same order', function()
    local first = buildList(vector4(1.0, 2.0, 3.0, 4.0))
    local firstIds = {}
    for _, entry in ipairs(first) do firstIds[#firstIds + 1] = entry.id end

    for _ = 1, 5 do
        local ids = {}
        for _, entry in ipairs(buildList(vector4(1.0, 2.0, 3.0, 4.0))) do ids[#ids + 1] = entry.id end
        H.equal(table.concat(ids, ','), table.concat(firstIds, ','), 'list order must be reproducible')
    end
end)

H.test('owned properties are appended in label order, behind every configured spawn', function()
    -- Keyed by house id, exactly as qb-houses returns them -- so the order
    -- this arrives in is whatever `pairs` feels like.
    ownedHouses = {
        h9 = { id = 'h9', label = 'Zeta Drive', coords = vector4(9.0, 9.0, 9.0, 0.0) },
        h1 = { id = 'h1', label = 'Alta Street', coords = vector4(1.0, 1.0, 1.0, 0.0) },
        h5 = { id = 'h5', label = 'Mirror Park', coords = vector4(5.0, 5.0, 5.0, 0.0) },
    }
    local locations = buildList(vector4(1.0, 2.0, 3.0, 4.0))
    ownedHouses = {}

    local tail = {}
    for index = #Config.spawns + 2, #locations do tail[#tail + 1] = locations[index].label end
    H.equal(table.concat(tail, ','), 'Alta Street,Mirror Park,Zeta Drive', 'houses must be label-ordered')
    H.equal(locations[#Config.spawns + 2].typeLoc, 'house', 'houses come after the configured spawns')
end)

------------------------------------------------------------------------------
-- Preview budget
------------------------------------------------------------------------------

H.test('the preview budget covers the whole flight plus world streaming', function()
    local budget = SceneRuntime.spawnPreviewBudgetMs()
    local flight = Config.spawnFlight
    local floor = flight.liftDurationMs + flight.maxTravelDurationMs + flight.descentDurationMs
        + Config.sceneLimits.worldStreamTimeoutMs

    H.truthy(budget > floor, 'the budget must exceed the flight plus one full world-stream timeout')
    -- The number the NUI used to hardcode. Keeping this here is the point: a
    -- preview is allowed to take longer than the UI once believed.
    H.truthy(budget > 15000, 'the real budget is nowhere near the old 15s NUI timeout')
    H.equal(budget, 16250, 'shipped-default preview budget')

    -- Down from 73250. The world-stream ceiling dropped from 30s to 8s once the
    -- preview started parking the player ped at the destination (the streamer's
    -- primary anchor) instead of waiting on a load scene from across the map,
    -- and the budget counts ONE stream rather than two now that a slow area is
    -- never abandoned for a fallback the player did not choose.
    H.truthy(budget < 20000, 'a preview that needs 20s is a bug, not patience')
end)

H.test('the preview budget is derived from config, so a raised timeout raises it', function()
    local before = SceneRuntime.spawnPreviewBudgetMs()

    Config.sceneLimits.worldStreamTimeoutMs = Config.sceneLimits.worldStreamTimeoutMs + 10000
    H.truthy(SceneRuntime.spawnPreviewBudgetMs() >= before + 10000,
        'a longer world-stream budget must widen the preview budget')

    Config.sceneLimits.worldStreamTimeoutMs = Config.sceneLimits.worldStreamTimeoutMs - 10000
    Config.spawnFlight.maxTravelDurationMs = Config.spawnFlight.maxTravelDurationMs + 5000
    H.equal(SceneRuntime.spawnPreviewBudgetMs(), before + 5000, 'a longer flight must widen it too')
    Config.spawnFlight.maxTravelDurationMs = Config.spawnFlight.maxTravelDurationMs - 5000

    H.equal(SceneRuntime.spawnPreviewBudgetMs(), before, 'and revert with the config')
end)

H.test('both spawn payloads carry the budget the NUI needs to size its timeout', function()
    local _, data = buildList(vector4(1.0, 2.0, 3.0, 4.0))
    H.equal(data.previewBudgetMs, SceneRuntime.spawnPreviewBudgetMs(),
        'the location list must ship the budget')
end)

H.test('a superseded preview is reported as a distinct, benign reason', function()
    -- The NUI keys its silence off this exact value; a rename here without a
    -- rename there brings back a failure toast per abandoned preview.
    H.equal(SceneRuntime.PREVIEW_SUPERSEDED, 'superseded', 'the cancellation reason is part of the NUI contract')
end)

------------------------------------------------------------------------------
-- qb-apartments handoff
------------------------------------------------------------------------------

local apartmentsState, triggered, serverEvents = 'missing', {}, {}
local timeouts = {}
_G.GetResourceState = function() return apartmentsState end
_G.TriggerEvent = function(name, ...) triggered[#triggered + 1] = { name = name, args = { ... } } end
_G.TriggerServerEvent = function(name, ...) serverEvents[#serverEvents + 1] = { name = name, args = { ... } } end
_G.SetTimeout = function(_, fn) timeouts[#timeouts + 1] = fn end
local nuiCallbacks = {}
_G.RegisterNUICallback = function(name, fn) nuiCallbacks[name] = fn end
_G.SetNuiFocus = function() end
_G.SceneRuntime = _G.SceneRuntime or {}
_G.multicharSetClientMode = function() end
local finished = {}
_G.multicharFinishSpawn = function(coords, isNew) finished[#finished + 1] = { coords = coords, isNew = isNew } end
Kora.callback.trigger = function(name)
    if name == 'qbmultichar:server:enterMode' then return true end
    return ownedHouses
end
dofile(root .. 'spawn.lua')

local apps = {
    apartment01 = { name = 'apartment01', label = 'South Rockford Plaza', coords = { enter = vector4(1.0, 2.0, 3.0, 4.0) } },
    apartment02 = { name = 'apartment02', label = 'Morningwood Blvd', coords = { enter = vector4(5.0, 6.0, 7.0, 8.0) } },
}

H.test('setupSpawns new=true builds the carousel from the apartment list only', function()
    nuiMessages = {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, true, apps)
    local payload = nuiMessages[#nuiMessages]
    H.equal(payload.data.isNew, true, 'flagged as new')
    H.equal(#payload.data.locations, 2, 'only apartments are offered')
    H.equal(payload.data.locations[1].apartmentType, 'apartment02', 'sorted by label')
    H.equal(payload.data.locations[2].typeLoc, 'apartment', 'apartment typeLoc')
end)

H.test('setupSpawns new=true without usable apps falls back to the default locations', function()
    nuiMessages = {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, true, nil)
    H.truthy(#nuiMessages[#nuiMessages].data.locations >= 1, 'defaults offered')
end)

H.test('choosing an apartment creates it through qb-apartments and finishes as a new character', function()
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, true, apps)
    apartmentsState = 'started'
    serverEvents, finished = {}, {}
    nuiCallbacks['multichar:spawn:choose']({ id = 'apartment:apartment01' }, function() end)
    H.equal(serverEvents[1].name, 'apartments:server:CreateApartment', 'stock event')
    H.equal(serverEvents[1].args[1], 'apartment01', 'type')
    H.equal(serverEvents[1].args[3], true, 'firstSpawn')
    H.equal(finished[1].isNew, true, 'new-character completion')
    apartmentsState = 'missing'
    serverEvents = {}
    nuiCallbacks['multichar:spawn:choose']({ id = 'apartment:apartment01' }, function() end)
    H.equal(#serverEvents, 0, 'no apartment creation when qb-apartments is not running')
end)

H.test('setupSpawnUI is routed only when qb-apartments is started, and openUI waits for it', function()
    apartmentsState = 'missing'
    triggered, nuiMessages = {}, {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, false, nil)
    H.equal(#triggered, 0, 'no apartments event without the resource')
    H.equal(nuiMessages[#nuiMessages].action, 'multichar:spawn:locations', 'locations published directly')

    apartmentsState = 'started'
    triggered, nuiMessages, timeouts = {}, {}, {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, false, nil)
    H.equal(triggered[1].name, 'apartments:client:setupSpawnUI', 'routed through qb-apartments')
    H.equal(#nuiMessages, 0, 'nothing published until apartments answers')
    netHandlers['qb-spawn:client:openUI'](true)
    H.equal(#nuiMessages, 0, 'openUI is held while apartments decides')

    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, false, nil)
    H.equal(nuiMessages[#nuiMessages].action, 'multichar:spawn:locations', 'apartments answer publishes locations')
    timeouts[1]()
    H.equal(nuiMessages[#nuiMessages].action, 'multichar:spawn:locations', 'stale timeout is a no-op')
end)

H.test('an unanswered apartments handoff times out into the default spawn picker', function()
    apartmentsState = 'started'
    nuiMessages, timeouts = {}, {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, false, nil)
    timeouts[1]()
    local actions = {}
    for _, message in ipairs(nuiMessages) do actions[#actions + 1] = message.action end
    H.equal(actions[1], 'multichar:spawn:locations', 'fallback publishes locations')
    H.equal(actions[2], 'multichar:spawn:show', 'fallback opens the picker')
    apartmentsState = 'missing'
end)

H.report('spawn')
