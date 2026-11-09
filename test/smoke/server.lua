local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local root = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local function vector(x, y, z, w) local value = { x = x, y = y, z = z }; value.w = w; return value end
_G.vector3 = function(x, y, z) return vector(x, y, z) end
_G.vector4 = function(x, y, z, w) return vector(x, y, z, w) end

local callbacks, handlers, exported, clientEvents = {}, {}, {}, {}
local buckets, states = { [7] = 42 }, { [7] = { ['qbcore:loggedIn'] = false } }
local invokingResource = nil

_G.GetCurrentResourceName = function() return 'kora_multichar' end
_G.GetInvokingResource = function() return invokingResource end
_G.GetPlayerRoutingBucket = function(src) return buckets[src] or 0 end
_G.SetPlayerRoutingBucket = function(src, bucket) buckets[src] = bucket end
local populationCalls = {}
_G.SetRoutingBucketPopulationEnabled = function(bucket, enabled) populationCalls[#populationCalls + 1] = { bucket = bucket, enabled = enabled } end
_G.Player = function(src)
    states[src] = states[src] or {}
    states[src].set = function(_, key, value) states[src][key] = value end
    return { state = states[src] }
end
_G.TriggerClientEvent = function(name, target, ...) clientEvents[#clientEvents + 1] = { name = name, target = target, args = { ... } } end
_G.AddEventHandler = function(name, callback) handlers[name] = handlers[name] or {}; handlers[name][#handlers[name] + 1] = callback end

local bucketNotices = {}
_G.TriggerEvent = function(name, src)
    if name == 'qbvoice:server:bucketChanged' then
        bucketNotices[#bucketNotices + 1] = { src = src, bucket = buckets[src] }
    end
end
local loggedOut = {}
local exportTable = {
    kora_core = { setPlayerBucket = function(_, src, bucket) buckets[src] = bucket; TriggerEvent('qbvoice:server:bucketChanged', src); return true end,
        logout = function(_, src)
            if not states[src] or states[src]['qbcore:loggedIn'] ~= true then return false end
            states[src]['qbcore:loggedIn'] = false
            loggedOut[#loggedOut + 1] = src
            return true
        end,
    },
}
_G.exports = setmetatable(exportTable, { __call = function(_, name, callback) exported[name] = callback end })

local heldLevel, permissionCalls = {}, {}
local commandDefs, notifications = {}, {}

_G.Kora = {
    util = { isFiniteNumber = function(value)
        return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
    end },
    callback = { register = function(name, callback) callbacks[name] = callback end },
    commands = { add = function(name, _, _, _, handler, opts) commandDefs[name] = { handler = handler, opts = opts or {} } end },
    notify = { send = function(src, payload) notifications[#notifications + 1] = { src = src, payload = payload } end },
    permissions = {
        hasLevel = function(src, required, levels, options)
            permissionCalls[#permissionCalls + 1] = { src = src, required = required, levels = levels, options = options }
            local held = heldLevel[src] or 'user'
            local heldIndex, requiredIndex
            for index, level in ipairs(levels) do
                if level == held then heldIndex = index end
                if level == required then requiredIndex = index end
            end
            return heldIndex ~= nil and requiredIndex ~= nil and heldIndex <= requiredIndex
        end,
    },
}

local function runCommand(name, src)
    local definition = assert(commandDefs[name], ('command %s was never registered'):format(name))
    local permission = definition.opts.permission or 'user'
    if permission ~= 'user' then
        local check = definition.opts.checkPermission
        if type(check) ~= 'function' or check(src, permission) ~= true then return false end
    end
    definition.handler(src)
    return true
end

local netEvents, clock, pedAt, players = {}, 0, {}, {}
_G.RegisterNetEvent = function(name, callback) netEvents[name] = callback end
_G.GetGameTimer = function() return clock end
_G.GetPlayers = function()
    local ids = {}
    for _, id in ipairs(players) do ids[#ids + 1] = tostring(id) end
    return ids
end
_G.GetPlayerPed = function(src) return pedAt[src] and src + 1000 or 0 end
_G.GetEntityCoords = function(handle) return pedAt[handle - 1000] end

dofile(root .. 'config.lua')
dofile(root .. 'shared/scene.lua')
dofile(root .. 'scenes.lua')
dofile(root .. 'server.lua')

H.test('selection and spawn modes preserve the original bucket until final cleanup', function()
    local ok = callbacks['qbmultichar:server:enterMode'](7, 'selection')
    H.truthy(ok, 'selection mode should open before login')
    H.equal(buckets[7], Config.buckets.selectionBase + 7, 'selection isolation bucket')
    H.equal(states[7]['qbmultichar:mode'], 'selection', 'selection state')

    states[7]['qbcore:loggedIn'] = true
    ok = callbacks['qbmultichar:server:enterMode'](7, 'spawn')
    H.truthy(ok, 'spawn should be a valid transition after login')
    H.equal(states[7]['qbmultichar:mode'], 'spawn', 'spawn state')
    H.equal(buckets[7], Config.buckets.selectionBase + 7, 'spawn retains isolated selection bucket')

    callbacks['qbmultichar:server:leaveMode'](7)
    H.equal(buckets[7], 42, 'cleanup restores pre-session bucket')
    H.equal(states[7]['qbmultichar:mode'], false, 'cleanup publishes an explicit cleared mode -- a nil deletion would not replicate to the client')
end)

H.test('creator command uses its own bucket and resource stop restores it', function()
    states[7]['qbcore:loggedIn'] = true
    heldLevel[7] = 'admin'
    H.truthy(runCommand(Config.creator.command, 7), 'an admin should reach the studio command')
    H.equal(buckets[7], Config.buckets.creatorBase + 7, 'creator isolation bucket')
    H.equal(states[7]['qbmultichar:mode'], 'creator', 'creator state')
    H.equal(clientEvents[#clientEvents].name, 'qbmultichar:client:openCreator', 'protected command opens client studio')

    for _, handler in ipairs(handlers.onResourceStop) do handler('kora_multichar') end
    H.equal(buckets[7], 42, 'resource stop restores original bucket')
    H.equal(states[7]['qbmultichar:mode'], false, 'resource stop publishes an explicit cleared mode')
end)

H.test('runtime scene ownership prevents cross-resource removal and stop sweeps owned scenes', function()
    invokingResource = 'taxi_resource'
    local ok, err = exported.RegisterScene('taxi_depot', Config.scenes.civilian)
    H.truthy(ok, err)
    local catalog = callbacks['qbmultichar:server:getScenes']()
    H.truthy(catalog.taxi_depot, 'registered scene should be visible')

    invokingResource = 'other_resource'
    ok = exported.UnregisterScene('taxi_depot')
    H.falsy(ok, 'another resource cannot remove the scene')

    invokingResource = nil
    for _, handler in ipairs(handlers.onResourceStop) do handler('taxi_resource') end
    catalog = callbacks['qbmultichar:server:getScenes']()
    H.falsy(catalog.taxi_depot, 'owner resource stop removes its scene')
    H.equal(clientEvents[#clientEvents].name, 'qbmultichar:client:sceneRemove', 'removal is broadcast')
end)

H.test('staff commands are gated through kora_lib permission levels, not a local rank table', function()
    heldLevel[7] = 'user'
    H.falsy(runCommand(Config.logout.command, 7), 'a plain user cannot log out staff-style')
    heldLevel[7] = 'mod'
    H.falsy(runCommand(Config.logout.command, 7), 'a mod is below the configured admin requirement')
    heldLevel[7] = 'god'
    states[7]['qbcore:loggedIn'] = true
    H.truthy(runCommand(Config.logout.command, 7), 'a god cascades past the admin requirement')

    local call = permissionCalls[#permissionCalls]
    H.equal(call.required, Config.logout.minimumPermission, 'the configured level is what gets checked')
    H.equal(call.levels[1], 'god', 'levels must be ordered most-privileged first')
    H.equal(call.options.prefix, 'qbcore', "staff levels resolve under qbcore's ace namespace")
end)

H.test('logout hands the drop to qbcore and never pushes character select itself', function()
    heldLevel[7] = 'admin'
    states[7]['qbcore:loggedIn'] = true
    loggedOut = {}
    local eventsBefore = #clientEvents

    H.truthy(runCommand(Config.logout.command, 7))
    H.equal(loggedOut[1], 7, 'the command must call qbcore logout')
    H.equal(states[7]['qbcore:loggedIn'], false, 'the replicated login state is what the client follows')
    H.equal(#clientEvents, eventsBefore, 'no client event: the login state bag is the only transport')
end)

H.test('logout refuses without a character and during a cinematic session', function()
    heldLevel[7] = 'admin'
    states[7]['qbcore:loggedIn'] = false
    loggedOut = {}
    H.truthy(runCommand(Config.logout.command, 7), 'permission passes; the handler itself refuses')
    H.equal(#loggedOut, 0, 'a player with no character is never logged out')

    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'selection'), 'selection opens before login')
    states[7]['qbcore:loggedIn'] = true
    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'spawn'), 'spawn follows the login')
    H.truthy(runCommand(Config.logout.command, 7))
    H.equal(#loggedOut, 0, 'a character cannot be dropped out from under the spawn carousel')
    H.equal(notifications[#notifications].payload.type, 'error', 'the refusal is reported to the player')

    callbacks['qbmultichar:server:leaveMode'](7)
    H.truthy(runCommand(Config.logout.command, 7))
    H.equal(loggedOut[1], 7, 'logout works again once the session is cleaned up')
end)

H.test('bucket notification covers the core and disabled-compat fallback exactly once', function()
    local compatSetter = exportTable.kora_core.setPlayerBucket
    for _, available in ipairs({ true, false }) do
        exportTable.kora_core.setPlayerBucket = available and compatSetter or function() error('compat disabled') end
        states[7]['qbcore:loggedIn'] = false
        bucketNotices = {}
        H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'selection'))
        H.equal(#bucketNotices, 1)
        H.equal(bucketNotices[1].src, 7)
        H.equal(bucketNotices[1].bucket, Config.buckets.selectionBase + 7, 'native changes before notification')
        bucketNotices = {}
        H.truthy(callbacks['qbmultichar:server:leaveMode'](7))
        H.equal(#bucketNotices, 1)
        H.equal(bucketNotices[1].src, 7)
        H.equal(bucketNotices[1].bucket, 42, 'restore notifies after native')
    end
    exportTable.kora_core.setPlayerBucket = compatSetter
end)

H.test('isolation buckets have population disabled, selection and creator alike', function()
    populationCalls = {}
    states[7]['qbcore:loggedIn'] = false
    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'selection'))
    H.equal(#populationCalls, 1, 'population is set once on entry')
    H.equal(populationCalls[1].bucket, Config.buckets.selectionBase + 7, 'selection bucket')
    H.equal(populationCalls[1].enabled, false, 'population disabled in the selection bucket')
    H.truthy(callbacks['qbmultichar:server:leaveMode'](7))

    states[7]['qbcore:loggedIn'] = true
    populationCalls = {}
    heldLevel[7] = 'admin'
    H.truthy(runCommand(Config.creator.command, 7), 'studio opens')
    H.equal(populationCalls[1].bucket, Config.buckets.creatorBase + 7, 'creator bucket')
    H.equal(populationCalls[1].enabled, false, 'population disabled in the creator bucket')
    callbacks['qbmultichar:server:leaveMode'](7)
    H.equal(buckets[7], 42, 'studio restores the previous bucket')
end)

H.test('selection to spawn keeps one bucket and restore happens once at spawn', function()
    states[7]['qbcore:loggedIn'] = false
    populationCalls = {}
    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'selection'))
    states[7]['qbcore:loggedIn'] = true
    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'spawn'))
    H.equal(buckets[7], Config.buckets.selectionBase + 7, 'spawn carousel stays isolated')
    H.equal(#populationCalls, 1, 'spawn does not re-isolate')
    H.truthy(callbacks['qbmultichar:server:leaveMode'](7))
    H.equal(buckets[7], 42, 'previous bucket restored when the player spawns into the world')
    H.equal(states[7]['qbmultichar:mode'], false, 'mode cleared')
end)

H.test('disablePopulation = false re-enables population on the bucket', function()
    Config.buckets.disablePopulation = false
    states[7]['qbcore:loggedIn'] = false
    populationCalls = {}
    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'selection'))
    H.equal(populationCalls[1].enabled, true, 'a stale disabled bucket follows the current setting')
    H.equal(buckets[7], Config.buckets.selectionBase + 7, 'still isolated')
    callbacks['qbmultichar:server:leaveMode'](7)
    Config.buckets.disablePopulation = true
end)

H.test('enabled = false never moves the player or touches population', function()
    Config.buckets.enabled = false
    states[7]['qbcore:loggedIn'] = false
    populationCalls = {}
    bucketNotices = {}
    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'selection'), 'the session itself still works')
    H.equal(buckets[7], 42, 'bucket untouched on entry')
    H.equal(states[7]['qbmultichar:mode'], 'selection', 'mode state still published')
    states[7]['qbcore:loggedIn'] = true
    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'spawn'))
    buckets[7] = 99
    H.truthy(callbacks['qbmultichar:server:leaveMode'](7))
    H.equal(buckets[7], 99, 'leave does not restore a bucket it never changed')
    H.equal(#populationCalls, 0, 'no population writes')
    H.equal(#bucketNotices, 0, 'no bucket notifications')
    Config.buckets.enabled = true
    buckets[7] = 42
end)

H.test('cleanup on resource stop restores isolated players', function()
    states[7]['qbcore:loggedIn'] = false
    H.truthy(callbacks['qbmultichar:server:enterMode'](7, 'selection'))
    for _, handler in ipairs(handlers['onResourceStop']) do handler('kora_multichar') end
    H.equal(buckets[7], 42, 'resource stop restores the previous bucket')
end)

H.test('nationality is validated against Config.nationalities', function()
    local validate = callbacks['qbmultichar:server:validateNationality']
    local list, free = Config.nationalities, Config.allowFreeTextNationality
    H.truthy(#list > 0 and list[1] ~= '', 'a default list ships')
    local ok, value = validate(7, '  ' .. list[1] .. ' ')
    H.truthy(ok, 'a listed value is accepted'); H.equal(value, list[1], 'and trimmed')
    H.falsy(validate(7, 'Quasar University'), 'free text is refused while a list is set')
    H.falsy(validate(7, nil), 'non-strings are refused')
    H.falsy(validate(7, { list[1] }), 'tables are refused')
    Config.allowFreeTextNationality = true
    H.truthy(validate(7, 'Quasar University'), 'free text allowed by the switch')
    H.falsy(validate(7, 'X'), 'free text still has a length floor')
    H.falsy(validate(7, string.rep('x', 33)), 'and a ceiling')
    Config.allowFreeTextNationality = false
    Config.nationalities = {}
    H.truthy(validate(7, 'Quasar University'), 'an empty list means free text')
    Config.nationalities, Config.allowFreeTextNationality = list, free
end)

H.test('closeNUI forwards to the caller and is refused during a cinematic session', function()
    clientEvents = {}
    runCommand('closeNUI', 31)
    H.equal(#clientEvents, 1, 'closeNUI must reach the caller')
    H.equal(clientEvents[1].name, 'qb-multicharacter:client:closeNUI', 'event name')
    H.equal(clientEvents[1].target, 31, 'only the caller is targeted')

    states[32] = { ['qbcore:loggedIn'] = false }
    callbacks['qbmultichar:server:enterMode'](32, 'selection')
    clientEvents = {}
    runCommand('closeNUI', 32)
    H.equal(#clientEvents, 0, 'closeNUI must not tear down an active session')
end)

H.test('GetServerLogs replies with an empty list', function()
    local result = callbacks['qb-multicharacter:server:GetServerLogs'](1)
    H.equal(type(result), 'table', 'table reply')
    H.equal(next(result), nil, 'empty reply')
end)

------------------------------------------------------------------------------
-- Arrival effect relay
------------------------------------------------------------------------------

local function relay(src, ...)
    _G.source = src
    clientEvents = {}
    netEvents['qbmultichar:server:arrivalEffect'](...)
    local sent = {}
    for _, event in ipairs(clientEvents) do
        if event.name == 'qbmultichar:client:arrivalEffect' then sent[#sent + 1] = event end
    end
    return sent
end

local function arrivalScene()
    clock = clock + 60000
    pedAt = {
        [21] = vector(100.0, 200.0, 30.0), [22] = vector(110.0, 205.0, 30.0), [23] = vector(900.0, 900.0, 30.0),
        [24] = vector(101.0, 201.0, 30.0), [25] = vector(60.0, 160.0, 30.0),
    }
    players = { 21, 22, 23, 24, 25 }
    buckets[21], buckets[22], buckets[23], buckets[24], buckets[25] = 0, 0, 0, 5, 0
    states[21] = { ['qbcore:loggedIn'] = true }
    Config.arrival.ptfx.enabled, Config.arrival.ptfx.synced, Config.arrival.ptfx.syncRadius = true, true, 150.0
end

H.test('an arrival effect is relayed to players nearby in the same bucket, and to nobody else', function()
    arrivalScene()
    local sent = relay(21, 100.0, 200.0, 29.0)
    local targets = {}
    for _, event in ipairs(sent) do targets[#targets + 1] = event.target end
    table.sort(targets)
    H.equal(table.concat(targets, ','), '22,25', 'near players in the same bucket; not the sender, the far player or the other bucket')
end)

H.test('what is relayed comes from the config, never from the client', function()
    arrivalScene()
    local sent = relay(21, 100.0, 200.0, 29.0, 'evil_asset', 'evil_effect', 99999)
    H.equal(#sent > 0, true, 'relayed')
    local args = sent[1].args
    H.equal(args[1], Config.arrival.ptfx.asset, 'asset is the configured one')
    H.equal(args[2], Config.arrival.ptfx.effect, 'effect is the configured one')
    H.equal(args[3], Config.arrival.ptfx.scale, 'scale is the configured one')
    H.equal(args[4], 100.0, 'the position is the one reported')
    H.equal(args[6], 29.0, 'including height')
end)

H.test('the visibility radius comes from the config', function()
    arrivalScene()
    Config.arrival.ptfx.syncRadius = 20.0
    local sent = relay(21, 100.0, 200.0, 29.0)
    H.equal(#sent, 1, 'only the player 11 m away; the one 56 m away is out of range')
    H.equal(sent[1].target, 22, 'the near player')
    Config.arrival.ptfx.syncRadius = 150.0
end)

H.test('nothing is relayed when syncing or the effect is switched off', function()
    arrivalScene()
    Config.arrival.ptfx.synced = false
    H.equal(#relay(21, 100.0, 200.0, 29.0), 0, 'synced = false')
    arrivalScene()
    Config.arrival.ptfx.enabled = false
    H.equal(#relay(21, 100.0, 200.0, 29.0), 0, 'enabled = false')
    arrivalScene()
end)

H.test('requests from a player who is not logged in, or without a ped, are ignored', function()
    arrivalScene()
    states[21]['qbcore:loggedIn'] = false
    H.equal(#relay(21, 100.0, 200.0, 29.0), 0, 'not logged in')
    arrivalScene()
    pedAt[21] = nil
    H.equal(#relay(21, 100.0, 200.0, 29.0), 0, 'no ped the server can see')
end)

H.test('a position far from where the server knows the player is, or not a number, is ignored', function()
    arrivalScene()
    H.equal(#relay(21, 600.0, 600.0, 30.0), 0, 'effect claimed 500 m from the player')
    for index, bad in ipairs({ { 'x', 200.0, 29.0 }, { 100.0, 0 / 0, 29.0 }, { 100.0, 200.0, math.huge }, { 100.0, 200.0 }, {} }) do
        arrivalScene()
        H.equal(#relay(21, table.unpack(bad, 1, 3)), 0, ('bad position %d'):format(index))
    end
end)

H.test('one player cannot flood the relay: a second request inside the cooldown is dropped', function()
    arrivalScene()
    H.truthy(#relay(21, 100.0, 200.0, 29.0) > 0, 'the first is relayed')
    clock = clock + 1000
    H.equal(#relay(21, 100.0, 200.0, 29.0), 0, 'a second a second later is not')
    clock = clock + 5000
    H.truthy(#relay(21, 100.0, 200.0, 29.0) > 0, 'allowed again after the cooldown')
end)

H.test('a player who drops loses their cooldown, so the slot is not held for the next occupant', function()
    arrivalScene()
    relay(21, 100.0, 200.0, 29.0)
    _G.source = 21
    for _, callback in ipairs(handlers.playerDropped or {}) do callback() end
    H.truthy(#relay(21, 100.0, 200.0, 29.0) > 0, 'a fresh connection on the same id is not rate-limited by the old one')
end)

H.report('server')
