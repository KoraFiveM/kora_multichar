-- Server authority for cinematic modes, scene registration, and the scene
-- studio command. Scene entities themselves are client-local; the server owns
-- only isolation, the replicated mode gate, and trusted resource definitions.

local scenes = {}
local sceneOwners = {}
local sessions = {} -- [src] = { previousBucket, mode, isolated }

local function setBucket(src, bucket)
    local ok = pcall(function() exports.kora_core:setPlayerBucket(src, bucket) end)
    if not ok then
        SetPlayerRoutingBucket(src, bucket)
        TriggerEvent('qbvoice:server:bucketChanged', src)
    end
end

-- Cleared mode is published as `false`, NOT as nil. Setting a state bag key to
-- nil is a DELETION, and a deletion does not replicate to the owning client the
-- way an ordinary value change does -- the client keeps reading the last mode
-- forever. Every consumer gates on this key (kora_hud's HUD stays hidden while a
-- cinematic mode is active, kora_clothing's first-character flow waits on it), so
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

-- Personal buckets (base + src) are never shared, so population can be switched
-- off per bucket without affecting anyone else. It is written on every entry
-- (true or false, from config) rather than once and then forgotten: slot numbers
-- are reused, so a stale disabled bucket must follow the current setting. There
-- is deliberately no restore on leave -- nobody is in the bucket afterwards, and
-- the next entry rewrites it. Entity lockdown is left untouched: the preview
-- scene's peds and vehicles are created client-side, so a strict lockdown would
-- only risk blocking them, and population is the thing being removed.
local function isolate(src, mode)
    local bucket = bucketFor(src, mode)
    setBucket(src, bucket)
    pcall(SetRoutingBucketPopulationEnabled, bucket, Config.buckets.disablePopulation == false)
end

local function enterMode(src, mode)
    if mode ~= 'selection' and mode ~= 'spawn' and mode ~= 'creator' then return false, 'invalid cinematic mode' end
    local session = sessions[src]
    if not session then
        -- Config.buckets.enabled = false never touches the player's bucket, so
        -- there is nothing to restore either (a restore could clobber a bucket
        -- another resource assigned in the meantime).
        local isolated = Config.buckets.enabled ~= false
        session = { previousBucket = isolated and GetPlayerRoutingBucket(src) or nil, mode = mode, isolated = isolated }
        sessions[src] = session
        if isolated then isolate(src, mode) end
    elseif mode == 'creator' and session.mode ~= 'creator' and session.isolated then
        isolate(src, mode)
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
    if session.isolated then setBucket(src, session.previousBucket or 0) end
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

Kora.callback.register('qbmultichar:server:getScenes', function()
    return SceneSchema.clone(scenes)
end)

Kora.callback.register('qbmultichar:server:enterMode', function(src, mode)
    local loggedIn = Player(src).state['qbcore:loggedIn'] == true
    if mode == 'selection' and loggedIn then return false, 'already logged in' end
    if mode == 'spawn' and (not sessions[src] or not loggedIn) then return false, 'spawn transition is not active' end
    if mode == 'creator' then return false, 'creator mode must be opened by the protected command' end
    return enterMode(src, mode)
end, { rateLimit = { max = 8, window = 10000 } })

Kora.callback.register('qbmultichar:server:leaveMode', leaveMode, { rateLimit = { max = 8, window = 10000 } })

---Checks a submitted nationality against Config.nationalities. With a list set
---and Config.allowFreeTextNationality off the value must be an entry of the
---list; otherwise any 2-32 character string is accepted.
---@param value any
---@return boolean ok
---@return string result the value to store, or the reason it was refused
local function validateNationality(value)
    if type(value) ~= 'string' then return false, 'Choose a valid nationality.' end
    value = value:match('^%s*(.-)%s*$')
    local list = Config.nationalities
    if type(list) == 'table' and #list > 0 and not Config.allowFreeTextNationality then
        for _, entry in ipairs(list) do
            if entry == value then return true, value end
        end
        return false, 'Choose a nationality from the list.'
    end
    if #value < 2 or #value > 32 then return false, 'Nationality must be between 2 and 32 characters.' end
    return true, value
end

Kora.callback.register('qbmultichar:server:validateNationality', function(_, value)
    return validateNationality(value)
end, { rateLimit = { max = 8, window = 10000 } })

-- Staff gating goes through kora_lib's permission gateway rather than a rank
-- table over kora_core's getPermission. Kora.permissions.hasLevel accepts either
-- `kora_core.<level>` or the bare `group.<level>` principal (which is how this
-- test server's server.cfg actually grants admin), folds in Discord roles
-- where a server maps them, and owns the cascade -- so a 'god' satisfies an
-- 'admin' requirement without chaining ace principals by hand.
local LEVELS = { 'god', 'admin', 'mod', 'user' } -- most-privileged first
local PERMISSION_OPTIONS = { prefix = 'qbcore' }

---Matches Kora.commands' checkPermission(source, permission) signature.
---@param src integer
---@param permission string|nil
---@return boolean
local function staffAllowed(src, permission)
    return Kora.permissions.hasLevel(src, permission or 'admin', LEVELS, PERMISSION_OPTIONS)
end

if Config.creator.enabled then
    Kora.commands.add(Config.creator.command, 'Open the cinematic multicharacter scene studio', nil, false, function(src)
        if Player(src).state['qbcore:loggedIn'] ~= true then
            Kora.notify.send(src, { type = 'error', message = 'Load a character before opening the scene studio.' })
            return
        end
        local ok, err = enterMode(src, 'creator')
        if not ok then
            Kora.notify.send(src, { type = 'error', message = err or 'Could not open the scene studio.' })
            return
        end
        TriggerClientEvent('qbmultichar:client:openCreator', src, SceneSchema.clone(scenes))
    end, {
        permission = Config.creator.minimumPermission,
        checkPermission = staffAllowed,
    })
end

-- Staff logout. This drops the character and keeps the connection; it does NOT
-- tell any client to reopen character select. kora_core's logout clears the
-- replicated `qbcore:loggedIn` state, and client.lua follows that state --
-- so an admin resource or a character delete on a live handle returns the
-- player to selection through exactly the same path this command does.
if Config.logout.enabled then
    Kora.commands.add(Config.logout.command, 'Drop your character and return to character select', nil, false, function(src)
        if Player(src).state['qbcore:loggedIn'] ~= true then
            Kora.notify.send(src, { type = 'error', message = 'You are not on a character.' })
            return
        end
        -- Refused mid-cinematic: selection/spawn/creator each own the player's
        -- routing bucket and camera, and tearing a character out from under
        -- one of them would strand the client in a scene with no character to
        -- return to. Leaving the studio or finishing the spawn is one keypress.
        if sessions[src] then
            Kora.notify.send(src, { type = 'error', message = 'Finish the current character-select session first.' })
            return
        end
        local ok, result = pcall(function() return exports.kora_core:logout(src) end)
        if not ok or result ~= true then
            Kora.notify.send(src, { type = 'error', message = 'Could not log out of that character.' })
        end
    end, {
        permission = Config.logout.minimumPermission,
        checkPermission = staffAllowed,
    })
end

-- Stock /closeNUI: asks the caller's own client to drop a stuck selection NUI.
-- Refused during a cinematic session, which owns the routing bucket and camera.
Kora.commands.add('closeNUI', 'Close the character selection screen if it is stuck', nil, false, function(src)
    if sessions[src] then
        Kora.notify.send(src, { type = 'error', message = 'Finish the current character-select session first.' })
        return
    end
    TriggerClientEvent('qb-multicharacter:client:closeNUI', src)
end)

-- Stock reads a server_logs table that kora has no equivalent of.
Kora.callback.register('qb-multicharacter:server:GetServerLogs', function()
    return {}
end)

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
