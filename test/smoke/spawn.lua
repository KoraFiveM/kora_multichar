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

_G.AddEventHandler = function() end
dofile(root .. 'scene.lua')

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
------------------------------------------------------------------------------

H.test('the preview budget covers the whole flight plus world streaming', function()
    local budget = SceneRuntime.spawnPreviewBudgetMs()
    local flight = Config.spawnFlight
    local floor = flight.liftDurationMs + flight.maxTravelDurationMs + flight.descentDurationMs
        + Config.sceneLimits.worldStreamTimeoutMs

    H.truthy(budget > floor, 'the budget must exceed the flight plus one full world-stream timeout')
    H.truthy(budget > 15000, 'the real budget is nowhere near the old 15s NUI timeout')
    H.equal(budget, 16250, 'shipped-default preview budget')

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
    H.equal(SceneRuntime.PREVIEW_SUPERSEDED, 'superseded', 'the cancellation reason is part of the NUI contract')
end)

------------------------------------------------------------------------------
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

------------------------------------------------------------------------------
-- One-screen select: list before login, Play, then the flight after login.
------------------------------------------------------------------------------

local clock = 0
_G.GetGameTimer = function() return clock end
_G.Wait = function() clock = clock + 100 end
local known, loaded, arrivals = { ABC12345 = true }, {}, {}
_G.multicharHasCharacter = function(citizenid) return known[citizenid] == true end
_G.multicharLoadCharacter = function(citizenid) loaded[#loaded + 1] = citizenid end
_G.multicharArrive = function(location, isNew) arrivals[#arrivals + 1] = { location = location, isNew = isNew } end

local function call(name, data)
    local reply
    nuiCallbacks[name](data, function(value) reply = value end)
    return reply
end

local function reset()
    apartmentsState = 'missing'
    ownedHouses, nuiMessages, triggered, serverEvents, finished = {}, {}, {}, {}, {}
    loaded, arrivals, timeouts = {}, {}, {}
    Config.arrival.enabled = true
    netHandlers['multichar:client:selectFailed'] = nil
    multicharPlayFailed()
end

local function lastError()
    for i = #nuiMessages, 1, -1 do
        if nuiMessages[i].action == 'multichar:error' then return nuiMessages[i].data end
    end
end

H.test('before login the list leads with a deferred last location, then the configured spawns, with no coordinates exposed', function()
    reset()
    local reply = call('multichar:spawn:list', { citizenid = 'ABC12345' })
    H.truthy(reply.ok, 'list answered')
    H.equal(reply.locations[1].id, 'current', 'last location leads')
    H.equal(reply.locations[1].label, 'Last Location', 'labelled for the player')
    H.equal(#reply.locations, #Config.spawns + 1, 'one entry per configured spawn')
    H.equal(reply.locations[2].id, Config.spawns[1].id, 'configured order is kept')
    for _, entry in ipairs(reply.locations) do
        H.falsy(entry.coords, 'coordinates stay in Lua')
        H.falsy(entry.preview, 'preview shots stay in Lua')
    end
end)

H.test('owned properties appear in the list for that character', function()
    reset()
    ownedHouses = { h1 = { id = 'h1', label = 'Alta Street', coords = vector4(1.0, 1.0, 1.0, 0.0) } }
    local reply = call('multichar:spawn:list', { citizenid = 'ABC12345' })
    local last = reply.locations[#reply.locations]
    H.equal(last.label, 'Alta Street', 'the property is offered')
    H.equal(last.typeLoc, 'house', 'typed as a house for the icon')
end)

H.test('the list is refused for a character that is not on this account, or when the feature is off', function()
    reset()
    H.falsy(call('multichar:spawn:list', { citizenid = 'SOMEONEELSE' }).ok, 'unknown character')
    H.falsy(call('multichar:spawn:list', {}).ok, 'no id')
    Config.arrival.enabled = false
    H.falsy(call('multichar:spawn:list', { citizenid = 'ABC12345' }).ok, 'feature off')
    reset()
end)

H.test('Play logs the character in through the same server event as Continue and waits for the answer', function()
    reset()
    local reply = call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' })
    H.truthy(reply.ok, 'accepted')
    H.equal(loaded[1], 'ABC12345', 'the character is logged in')
    H.equal(#arrivals, 0, 'no flight until the login has happened')
    H.equal(#finished, 0, 'no spawn either')
end)

H.test('Play rejects an arrival point that character does not have, a stranger, and a second press', function()
    reset()
    local bad = call('multichar:play', { citizenid = 'ABC12345', locationId = 'atlantis' })
    H.falsy(bad.ok, 'unknown arrival point')
    H.truthy(lastError(), 'the player is told')
    H.equal(#loaded, 0, 'and nobody is logged in')
    H.falsy(call('multichar:play', { citizenid = 'NOPE', locationId = 'legion' }).ok, 'unknown character')
    H.falsy(call('multichar:play', { citizenid = 'ABC12345' }).ok, 'no arrival point')
    H.truthy(call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' }).ok, 'a valid play')
    H.falsy(call('multichar:play', { citizenid = 'ABC12345', locationId = 'pillbox' }).ok, 'a second press while logging in')
    H.equal(#loaded, 1, 'only one login')
end)

H.test('after login the chosen arrival point starts the flight, and the old picker never opens', function()
    reset()
    call('multichar:play', { citizenid = 'ABC12345', locationId = 'pillbox' })
    nuiMessages = {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345', position = vector4(5.0, 6.0, 7.0, 8.0) }, false, nil)
    netHandlers['qb-spawn:client:openUI'](true)
    H.equal(#arrivals, 1, 'one flight')
    H.equal(arrivals[1].location.id, 'pillbox', 'to the point that was chosen')
    H.equal(arrivals[1].location.coords.x, Config.spawns[2].coords.x, 'with its real coordinates')
    H.truthy(arrivals[1].location.preview, 'and its authored arrival shot')
    H.equal(arrivals[1].isNew, false, 'an existing character')
    for _, message in ipairs(nuiMessages) do
        H.falsy(message.action == 'multichar:spawn:show' or message.action == 'multichar:spawn:locations', 'the spawn picker is not shown')
    end
end)

H.test('Last Location gets its real coordinates from the saved position once logged in', function()
    reset()
    call('multichar:play', { citizenid = 'ABC12345', locationId = 'current' })
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345', position = vector4(5.0, 6.0, 7.0, 8.0) }, false, nil)
    netHandlers['qb-spawn:client:openUI'](true)
    H.equal(arrivals[1].location.id, 'current', 'flies to the last location')
    H.equal(arrivals[1].location.coords.x, 5.0, 'at the saved position')
    H.equal(arrivals[1].location.coords.w, 8.0, 'facing the saved heading')
end)

H.test('with no saved position, Last Location falls back to the first configured spawn instead of stranding the player', function()
    reset()
    call('multichar:play', { citizenid = 'ABC12345', locationId = 'current' })
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, false, nil)
    netHandlers['qb-spawn:client:openUI'](true)
    H.equal(#arrivals, 1, 'still flies')
    H.equal(arrivals[1].location.id, Config.spawns[1].id, 'to the first configured spawn')
end)

H.test('openUI arriving before the list is built waits for it rather than opening the picker', function()
    reset()
    call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' })
    local waits = 0
    local plainWait = _G.Wait
    _G.Wait = function()
        waits = waits + 1
        if waits == 3 then
            netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, false, nil)
        end
        plainWait()
    end
    nuiMessages = {}
    netHandlers['qb-spawn:client:openUI'](true)
    _G.Wait = plainWait
    H.equal(#arrivals, 1, 'the flight starts once the list is ready')
    H.equal(arrivals[1].location.id, 'legion', 'to the chosen point')
    H.equal(#nuiMessages, 0, 'and the picker stays closed')
end)

H.test('qb-apartments routing and brand-new characters keep the spawn picker, and cancel the pending Play', function()
    reset()
    call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' })
    apartmentsState = 'started'
    triggered = {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, false, nil)
    H.equal(triggered[1] and triggered[1].name, 'apartments:client:setupSpawnUI', 'the legacy apartments route runs')
    netHandlers['qb-spawn:client:openUI'](true)
    H.equal(#arrivals, 0, 'no flight over the legacy route')

    reset()
    call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' })
    nuiMessages = {}
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345' }, true, nil)
    H.equal(nuiMessages[#nuiMessages].action, 'multichar:spawn:locations', 'a new character gets the picker list')
    netHandlers['qb-spawn:client:openUI'](true)
    H.equal(#arrivals, 0, 'no flight for the legacy picker path')
end)

H.test('a login that never answers clears the Play, tells the player, and lets them try again', function()
    reset()
    call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' })
    H.equal(#timeouts, 1, 'a watchdog was set')
    timeouts[1]()
    H.truthy(lastError(), 'the player is told')
    H.truthy(call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' }).ok, 'and can press Play again')
end)

H.test('a server-side refusal clears the Play so the next press works', function()
    reset()
    call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' })
    H.falsy(call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' }).ok, 'blocked while pending')
    multicharPlayFailed()
    H.truthy(call('multichar:play', { citizenid = 'ABC12345', locationId = 'legion' }).ok, 'allowed again')
end)

H.test('without a pending Play the original flow is untouched: openUI opens the picker', function()
    reset()
    netHandlers['qb-spawn:client:setupSpawns']({ citizenid = 'ABC12345', position = vector4(5.0, 6.0, 7.0, 8.0) }, false, nil)
    nuiMessages = {}
    netHandlers['qb-spawn:client:openUI'](true)
    local opened = false
    for _, message in ipairs(nuiMessages) do if message.action == 'multichar:spawn:show' then opened = true end end
    H.truthy(opened, 'the picker still opens for the Continue flow')
    H.equal(#arrivals, 0, 'and no flight starts')
end)

H.report('spawn')
