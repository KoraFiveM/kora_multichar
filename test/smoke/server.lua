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

local loggedOut = {}
local exportTable = {
    ['qb-core'] = { SetPlayerBucket = function(_, src, bucket) buckets[src] = bucket; return true end },
    qbcore = {
        -- Mirrors Core.player.logout: clears the replicated login state (which
        -- is the ONLY thing the client follows back to selection) and reports
        -- false when there is no player handle to drop.
        logout = function(_, src)
            if not states[src] or states[src]['qbcore:loggedIn'] ~= true then return false end
            states[src]['qbcore:loggedIn'] = false
            loggedOut[#loggedOut + 1] = src
            return true
        end,
    },
}
_G.exports = setmetatable(exportTable, { __call = function(_, name, callback) exported[name] = callback end })

-- Held staff level per source, resolved through a faithful copy of
-- QB.permissions.hasLevel's cascade (levels ordered most-privileged first).
local heldLevel, permissionCalls = {}, {}
local commandDefs, notifications = {}, {}

_G.QB = {
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

-- Mirrors qblib's command dispatcher: a non-'user' permission needs a
-- checkPermission that returns true, or the command never reaches its handler.
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

    for _, handler in ipairs(handlers.onResourceStop) do handler('qbmultichar') end
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

H.test('staff commands are gated through qblib permission levels, not a local rank table', function()
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

    -- Walk the real transition: selection opens pre-login, spawn follows it.
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

H.report('server')
