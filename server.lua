-- Server authority for cinematic modes, scene registration, and the scene
-- studio command. Scene entities themselves are client-local; the server owns
-- only isolation, the replicated mode gate, and trusted resource definitions.

local scenes = {}
local sceneOwners = {}
local sessions = {} -- [src] = { previousBucket, mode }

local function setBucket(src, bucket)
    local ok = pcall(function() exports['qb-core']:SetPlayerBucket(src, bucket) end)
    if not ok then SetPlayerRoutingBucket(src, bucket) end
end

-- Cleared mode is published as `false`, NOT as nil. Setting a state bag key to
-- nil is a DELETION, and a deletion does not replicate to the owning client the
-- way an ordinary value change does -- the client keeps reading the last mode
-- forever. Every consumer gates on this key (qbhud's HUD stays hidden while a
-- cinematic mode is active, qbclothing's first-character flow waits on it), so
-- a clear that never lands leaves the HUD hidden for the whole session. An
-- explicit falsy value keeps the clear a normal replicated change. Readers
-- treat nil and false alike, so nothing breaks if this key was never set.
local NO_MODE = false

local function writeMode(src, mode)
    Player(src).state:set('qbmultichar:mode', mode or NO_MODE, true)
end

local function bucketFor(src, mode)
    local base = mode == 'creator' and Config.buckets.creatorBase or Config.buckets.selectionBase
    return base + src
end

local function enterMode(src, mode)
    if mode ~= 'selection' and mode ~= 'spawn' and mode ~= 'creator' then return false, 'invalid cinematic mode' end
    local session = sessions[src]
    if not session then
        session = { previousBucket = GetPlayerRoutingBucket(src), mode = mode }
        sessions[src] = session
        setBucket(src, bucketFor(src, mode))
    elseif mode == 'creator' and session.mode ~= 'creator' then
        setBucket(src, bucketFor(src, mode))
    end
    session.mode = mode
    writeMode(src, mode)
    return true
end

local function leaveMode(src)
    local session = sessions[src]
    if not session then
        writeMode(src, nil)
        return true
    end
    setBucket(src, session.previousBucket or 0)
    sessions[src] = nil
    writeMode(src, nil)
    return true
end

local function sceneCount()
    local count = 0
    for _ in pairs(scenes) do count = count + 1 end
    return count
end

local function registerScene(owner, id, definition, broadcast)
    local existingOwner = sceneOwners[id]
    if existingOwner and existingOwner ~= owner then return false, ('scene %s is owned by %s'):format(id, existingOwner) end
    if not existingOwner and sceneCount() >= Config.sceneLimits.maxScenes then return false, 'scene registry is full' end
    local normalized, err = SceneSchema.validate(id, definition, Config.sceneLimits)
    if not normalized then return false, err end
    scenes[id], sceneOwners[id] = normalized, owner
    if broadcast then TriggerClientEvent('qbmultichar:client:sceneUpsert', -1, id, normalized) end
    return true
end

local function unregisterScene(owner, id, broadcast)
    if not scenes[id] then return false, 'unknown scene' end
    if sceneOwners[id] ~= owner then return false, 'scene is owned by another resource' end
    scenes[id], sceneOwners[id] = nil, nil
    if broadcast then TriggerClientEvent('qbmultichar:client:sceneRemove', -1, id) end
    return true
end

local configuredIds = {}
for id in pairs(Config.scenes or {}) do configuredIds[#configuredIds + 1] = id end
table.sort(configuredIds)
for _, id in ipairs(configuredIds) do
    local definition = Config.scenes[id]
    local ok, err = registerScene(GetCurrentResourceName(), id, definition, false)
    if not ok then print(('^1[qbmultichar]^7 bundled scene %s rejected: %s'):format(tostring(id), tostring(err))) end
end

exports('RegisterScene', function(id, definition)
    return registerScene(GetInvokingResource() or GetCurrentResourceName(), id, definition, true)
end)

exports('UnregisterScene', function(id)
    return unregisterScene(GetInvokingResource() or GetCurrentResourceName(), id, true)
end)

QB.callback.register('qbmultichar:server:getScenes', function()
    return SceneSchema.clone(scenes)
end)

QB.callback.register('qbmultichar:server:enterMode', function(src, mode)
    local loggedIn = Player(src).state['qbcore:loggedIn'] == true
    if mode == 'selection' and loggedIn then return false, 'already logged in' end
    if mode == 'spawn' and (not sessions[src] or not loggedIn) then return false, 'spawn transition is not active' end
    if mode == 'creator' then return false, 'creator mode must be opened by the protected command' end
    return enterMode(src, mode)
end, { rateLimit = { max = 8, window = 10000 } })

QB.callback.register('qbmultichar:server:leaveMode', function(src)
    return leaveMode(src)
end, { rateLimit = { max = 8, window = 10000 } })

-- Staff gating goes through qblib's permission gateway rather than a rank
-- table over qbcore's getPermission. QB.permissions.hasLevel accepts either
-- `qbcore.<level>` or the bare `group.<level>` principal (which is how this
-- test server's server.cfg actually grants admin), folds in Discord roles
-- where a server maps them, and owns the cascade -- so a 'god' satisfies an
-- 'admin' requirement without chaining ace principals by hand.
local LEVELS = { 'god', 'admin', 'mod', 'user' } -- most-privileged first
local PERMISSION_OPTIONS = { prefix = 'qbcore' }

---Matches QB.commands' checkPermission(source, permission) signature.
---@param src integer
---@param permission string|nil
---@return boolean
local function staffAllowed(src, permission)
    return QB.permissions.hasLevel(src, permission or 'admin', LEVELS, PERMISSION_OPTIONS)
end

if Config.creator.enabled then
    QB.commands.add(Config.creator.command, 'Open the cinematic multicharacter scene studio', nil, false, function(src)
        if Player(src).state['qbcore:loggedIn'] ~= true then
            QB.notify.send(src, { type = 'error', message = 'Load a character before opening the scene studio.' })
            return
        end
        local ok, err = enterMode(src, 'creator')
        if not ok then
            QB.notify.send(src, { type = 'error', message = err or 'Could not open the scene studio.' })
            return
        end
        TriggerClientEvent('qbmultichar:client:openCreator', src, SceneSchema.clone(scenes))
    end, {
        permission = Config.creator.minimumPermission,
        checkPermission = staffAllowed,
    })
end

-- Staff logout. This drops the character and keeps the connection; it does NOT
-- tell any client to reopen character select. qbcore's logout clears the
-- replicated `qbcore:loggedIn` state, and client.lua follows that state --
-- so an admin resource or a character delete on a live handle returns the
-- player to selection through exactly the same path this command does.
if Config.logout.enabled then
    QB.commands.add(Config.logout.command, 'Drop your character and return to character select', nil, false, function(src)
        if Player(src).state['qbcore:loggedIn'] ~= true then
            QB.notify.send(src, { type = 'error', message = 'You are not on a character.' })
            return
        end
        -- Refused mid-cinematic: selection/spawn/creator each own the player's
        -- routing bucket and camera, and tearing a character out from under
        -- one of them would strand the client in a scene with no character to
        -- return to. Leaving the studio or finishing the spawn is one keypress.
        if sessions[src] then
            QB.notify.send(src, { type = 'error', message = 'Finish the current character-select session first.' })
            return
        end
        local ok, result = pcall(function() return exports.qbcore:logout(src) end)
        if not ok or result ~= true then
            QB.notify.send(src, { type = 'error', message = 'Could not log out of that character.' })
        end
    end, {
        permission = Config.logout.minimumPermission,
        checkPermission = staffAllowed,
    })
end

AddEventHandler('playerDropped', function()
    sessions[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for src in pairs(sessions) do pcall(leaveMode, src) end
        return
    end
    local removed = {}
    for id, owner in pairs(sceneOwners) do
        if owner == resource then removed[#removed + 1] = id end
    end
    for _, id in ipairs(removed) do unregisterScene(resource, id, true) end
end)
