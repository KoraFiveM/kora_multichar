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

_G.GetCurrentResourceName = function() return 'qbmultichar' end
_G.GetInvokingResource = function() return invokingResource end
_G.GetPlayerRoutingBucket = function(src) return buckets[src] or 0 end
_G.SetPlayerRoutingBucket = function(src, bucket) buckets[src] = bucket end
_G.Player = function(src)
    states[src] = states[src] or {}
    states[src].set = function(_, key, value) states[src][key] = value end
    return { state = states[src] }
end
_G.TriggerClientEvent = function(name, target, ...) clientEvents[#clientEvents + 1] = { name = name, target = target, args = { ... } } end
_G.AddEventHandler = function(name, callback) handlers[name] = handlers[name] or {}; handlers[name][#handlers[name] + 1] = callback end

local exportTable = {
    ['qb-core'] = { SetPlayerBucket = function(_, src, bucket) buckets[src] = bucket; return true end },
    qbcore = { getPermission = function() return 'admin' end },
}
_G.exports = setmetatable(exportTable, { __call = function(_, name, callback) exported[name] = callback end })
_G.QB = {
    callback = { register = function(name, callback) callbacks[name] = callback end },
    commands = { add = function(_, _, _, _, callback) callbacks.creatorCommand = callback end },
    notify = { send = function() end },
}

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
    H.equal(states[7]['qbmultichar:mode'], nil, 'cleanup clears replicated mode')
end)

H.test('creator command uses its own bucket and resource stop restores it', function()
    states[7]['qbcore:loggedIn'] = true
    callbacks.creatorCommand(7)
    H.equal(buckets[7], Config.buckets.creatorBase + 7, 'creator isolation bucket')
    H.equal(states[7]['qbmultichar:mode'], 'creator', 'creator state')
    H.equal(clientEvents[#clientEvents].name, 'qbmultichar:client:openCreator', 'protected command opens client studio')

    for _, handler in ipairs(handlers.onResourceStop) do handler('qbmultichar') end
    H.equal(buckets[7], 42, 'resource stop restores original bucket')
    H.equal(states[7]['qbmultichar:mode'], nil, 'resource stop clears creator state')
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

H.report('server')
