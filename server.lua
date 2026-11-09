local scenes = {}
local sceneOwners = {}
local sessions = {}

local function setBucket(src, bucket)
    local ok = pcall(function() exports.kora_core:setPlayerBucket(src, bucket) end)
    if not ok then
        SetPlayerRoutingBucket(src, bucket)
        TriggerEvent('qbvoice:server:bucketChanged', src)
    end
end

local NO_MODE = false

local function writeMode(src, mode)
    Player(src).state:set('qbmultichar:mode', mode or NO_MODE, true)
end

local function bucketFor(src, mode)
    local base = mode == 'creator' and Config.buckets.creatorBase or Config.buckets.selectionBase
    return base + src
end

local function isolate(src, mode)
    local bucket = bucketFor(src, mode)
    setBucket(src, bucket)
    pcall(SetRoutingBucketPopulationEnabled, bucket, Config.buckets.disablePopulation == false)
end

local function enterMode(src, mode)
    if mode ~= 'selection' and mode ~= 'spawn' and mode ~= 'creator' then return false, 'invalid cinematic mode' end
    local session = sessions[src]
    if not session then
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

local LEVELS = { 'god', 'admin', 'mod', 'user' }
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

if Config.logout.enabled then
    Kora.commands.add(Config.logout.command, 'Drop your character and return to character select', nil, false, function(src)
        if Player(src).state['qbcore:loggedIn'] ~= true then
            Kora.notify.send(src, { type = 'error', message = 'You are not on a character.' })
            return
        end
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

Kora.commands.add('closeNUI', 'Close the character selection screen if it is stuck', nil, false, function(src)
    if sessions[src] then
        Kora.notify.send(src, { type = 'error', message = 'Finish the current character-select session first.' })
        return
    end
    TriggerClientEvent('qb-multicharacter:client:closeNUI', src)
end)

-- The arrival effect, shown to players near the arrival.
--
-- The arriving client reports only WHERE it played the effect. What is played
-- is read from Config here, so a client cannot make others load an arbitrary
-- asset or effect. The position must be near where the server knows that
-- player's ped is, the request is rate-limited per player, and only players in
-- the same routing bucket and within Config.arrival.ptfx.syncRadius are told.
local ARRIVAL_EFFECT_COOLDOWN_MS = 5000
local ARRIVAL_EFFECT_MAX_FEET_DISTANCE = 25.0
local lastArrivalEffect = {}

local function distance3(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

RegisterNetEvent('qbmultichar:server:arrivalEffect', function(x, y, z)
    local src = source
    local config = Config.arrival and Config.arrival.ptfx
    if type(config) ~= 'table' or config.enabled == false or config.synced ~= true then return end
    if Player(src).state['qbcore:loggedIn'] ~= true then return end
    if not (Kora.util.isFiniteNumber(x) and Kora.util.isFiniteNumber(y) and Kora.util.isFiniteNumber(z)) then return end

    local now = GetGameTimer()
    if lastArrivalEffect[src] and now - lastArrivalEffect[src] < ARRIVAL_EFFECT_COOLDOWN_MS then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local origin = GetEntityCoords(ped)
    if distance3(origin.x, origin.y, origin.z, x, y, z) > ARRIVAL_EFFECT_MAX_FEET_DISTANCE then return end
    lastArrivalEffect[src] = now

    local bucket = GetPlayerRoutingBucket(src)
    local radius = tonumber(config.syncRadius) or 150.0
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target and target ~= src and GetPlayerRoutingBucket(target) == bucket then
            local targetPed = GetPlayerPed(target)
            if targetPed and targetPed ~= 0 then
                local at = GetEntityCoords(targetPed)
                if distance3(at.x, at.y, at.z, origin.x, origin.y, origin.z) <= radius then
                    TriggerClientEvent('qbmultichar:client:arrivalEffect', target,
                        config.asset, config.effect, tonumber(config.scale) or 1.0, x, y, z)
                end
            end
        end
    end
end)

Kora.callback.register('qb-multicharacter:server:GetServerLogs', function()
    return {}
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    lastArrivalEffect[source] = nil
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
