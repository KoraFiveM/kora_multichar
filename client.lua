local characters = {}
local charactersById = {}
local maxCharacters = 5
local sceneCatalog = {}
local selectedCharacter = nil
local previewGeneration = 0
local currentMode = nil

exports.kora_core:claimUI()

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function nextFreeSlot(list)
    local taken = {}
    for _, character in ipairs(list) do taken[character.cid] = true end
    for cid = 1, maxCharacters do if not taken[cid] then return cid end end
    return nil
end

local function setCharacters(list)
    characters, charactersById = list or {}, {}
    for _, character in ipairs(characters) do charactersById[character.citizenid] = character end
end

local function fallbackModel(character)
    return character and character.charinfo and tonumber(character.charinfo.gender) == 1
        and 'mp_f_freemode_01' or 'mp_m_freemode_01'
end

local BOOT_RETRY_MS = 2000
local BOOT_MAX_ATTEMPTS = 8

---Retries `attempt` until it returns a non-nil value. `attempt` returns nil for
---"no answer, try again" and any other value for "answered".
---@param attempts integer|nil defaults to BOOT_MAX_ATTEMPTS
local function bootCall(label, attempt, attempts)
    attempts = attempts or BOOT_MAX_ATTEMPTS
    for tries = 1, attempts do
        local ok, value = pcall(attempt)
        if ok and value ~= nil then return value end
        if tries < attempts then
            print(('^3[kora_multichar]^7 %s did not answer (attempt %d/%d) -- retrying in %dms')
                :format(label, tries, attempts, BOOT_RETRY_MS))
            Wait(BOOT_RETRY_MS)
        end
    end
    print(('^1[kora_multichar]^7 %s never answered after %d attempt(s).'):format(label, attempts))
    return nil
end

---@param attempts integer|nil
local function fetchSceneCatalog(attempts)
    return bootCall('scene catalog fetch', function()
        local fetched = Kora.callback.trigger('kora_multichar:server:getScenes')
        if type(fetched) ~= 'table' or next(fetched) == nil then return nil end
        return fetched
    end, attempts)
end

local function refetchScenesIfEmpty()
    if next(sceneCatalog) ~= nil then return end
    sceneCatalog = fetchSceneCatalog(1) or {}
end

local function previewCharacter(citizenid)
    local character = charactersById[citizenid]
    if not character then return end
    selectedCharacter = character
    previewGeneration = previewGeneration + 1
    local generation = previewGeneration
    send('multichar:previewLoading', { citizenid = citizenid })

    CreateThread(function()
        local ok, model, skin = pcall(function()
            return Kora.callback.trigger('qb-multicharacter:server:getSkin', citizenid)
        end)
        if not ok then
            print(('^3[kora_multichar]^7 skin fetch failed, using default model: %s'):format(tostring(model)))
            model, skin = nil, nil
        end
        if generation ~= previewGeneration then return end
        if type(model) ~= 'string' then model, skin = fallbackModel(character), {} end
        refetchScenesIfEmpty()
        if generation ~= previewGeneration then return end
        local scene, sceneId = SceneSchema.resolve(sceneCatalog, character, Config.defaultScene)
        local loaded, err = SceneRuntime.loadCharacter(scene, model, skin)
        if generation ~= previewGeneration or err == 'stale preview' then return end
        if not loaded and sceneId ~= Config.defaultScene then
            sceneId, scene = Config.defaultScene, sceneCatalog[Config.defaultScene]
            loaded, err = SceneRuntime.loadCharacter(scene, model, skin)
            if generation ~= previewGeneration or err == 'stale preview' then return end
        end
        if not loaded then
            model, skin = fallbackModel(character), {}
            sceneId, scene = Config.defaultScene, sceneCatalog[Config.defaultScene]
            loaded, err = SceneRuntime.loadCharacter(scene, model, skin)
        end
        if generation ~= previewGeneration or err == 'stale preview' then return end
        send('multichar:previewReady', {
            citizenid = citizenid,
            scene = sceneId,
            ok = loaded == true,
            error = loaded and nil or err,
        })
    end)
end

local function leaveServerMode()
    return Kora.callback.trigger('kora_multichar:server:leaveMode') == true
end

local function closeNuiOnly()
    currentMode = nil
    SetNuiFocus(false, false)
    send('multichar:close')
end

local pendingNewCharacter = false

local function announceSpawnComplete(isNew)
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        while not IsScreenFadedIn() and GetGameTimer() < deadline do Wait(0) end
        TriggerEvent('kora_multichar:client:spawnComplete', isNew == true)
    end)
end

local function resetNewCharacterAppearance()
    if Config.newCharacter and Config.newCharacter.resetAppearance == false then return end
    if GetResourceState('kora_clothing') ~= 'started' then return end
    local ok, err = pcall(function() return exports.kora_clothing:applyStarterAppearance() end)
    if not ok then
        print(('^3[kora_multichar]^7 starter outfit could not be applied: %s'):format(tostring(err)))
    end
end

local function finishAt(coords, forceNew)
    previewGeneration = previewGeneration + 1
    local isNew = pendingNewCharacter or forceNew == true
    pendingNewCharacter = false

    DoScreenFadeOut(250)
    local deadline = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
    SceneRuntime.endMode()
    leaveServerMode()
    if isNew then resetNewCharacterAppearance() end
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    SetEntityHeading(ped, coords.w or coords.h or 0.0)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.w or coords.h or 0.0, 0, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    closeNuiOnly()
    DoScreenFadeIn(500)
    announceSpawnComplete(isNew)
end

function multicharFinishSpawn(coords, isNew)
    finishAt(coords, isNew)
end

local function arrivalEnabled()
    return (Config.arrival or {}).enabled ~= false
end

---Whether the id belongs to a character in the list this session was shown.
---spawn.lua's Play handler uses it so it never logs in an id the list lacks.
function multicharHasCharacter(citizenid)
    return type(citizenid) == 'string' and charactersById[citizenid] ~= nil
end

---Logs a listed character in. Same server event the Continue button uses; the
---server answers with qb-spawn:client:setupSpawns / openUI, which spawn.lua
---turns into the arrival flight when a Play is pending.
function multicharLoadCharacter(citizenid)
    selectedCharacter = charactersById[citizenid]
    TriggerServerEvent('qb-multicharacter:server:loadUserData', { citizenid = citizenid })
end

local function selectedCharacterName()
    local info = selectedCharacter and selectedCharacter.charinfo
    if not info then return nil end
    local name = ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$')
    return name ~= '' and name or nil
end

---The arrival: the camera flies from the character scene to the arrival
---point, then the ped appears there. Takes the place of finishAt's fade-out,
---teleport, fade-in; if the flight cannot run it falls back to exactly that,
---so a failed flight can never strand a player on the select screen.
---@param location table { label, coords = vector4, preview = table|nil }
---@param forceNew boolean|nil
function multicharArrive(location, forceNew)
    previewGeneration = previewGeneration + 1
    local isNew = pendingNewCharacter or forceNew == true
    pendingNewCharacter = false
    local config = Config.arrival or {}

    SetNuiFocus(false, false)
    send('multichar:flight:start', {
        location = location.label,
        character = selectedCharacterName(),
        skippable = config.skippable ~= false,
    })

    SceneRuntime.preloadArrivalEffect(config.ptfx)
    local ok, reason = SceneRuntime.flyToArrival(location, {
        skippable = config.skippable ~= false,
        onStage = function(stage) send('multichar:flight:stage', { stage = stage }) end,
    })
    if not ok then
        print(('^3[kora_multichar]^7 arrival flight did not complete (%s); using a plain spawn.'):format(tostring(reason)))
        SceneRuntime.releaseArrivalEffect()
        finishAt(location.coords, isNew)
        return
    end

    leaveServerMode()
    if isNew then resetNewCharacterAppearance() end
    SceneRuntime.completeArrival(location.coords, {
        settleMs = config.settleMs,
        pedFadeMs = config.pedFadeMs,
        handbackMs = config.handbackMs,
        zOffset = config.zOffset,
        ptfx = config.ptfx,
        onPlaced = function() TriggerServerEvent('QBCore:Server:OnPlayerLoaded') end,
    })
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    closeNuiOnly()
    announceSpawnComplete(isNew)
end

function multicharSetClientMode(mode)
    previewGeneration = previewGeneration + 1
    currentMode = mode
end

local function refreshCharacters()
    previewGeneration = previewGeneration + 1
    local entered, enterErr
    for tries = 1, BOOT_MAX_ATTEMPTS do
        entered, enterErr = Kora.callback.trigger('kora_multichar:server:enterMode', 'selection')
        if entered ~= nil then break end
        print(('^3[kora_multichar]^7 selection handshake did not answer (attempt %d/%d) -- retrying in %dms')
            :format(tries, BOOT_MAX_ATTEMPTS, BOOT_RETRY_MS))
        Wait(BOOT_RETRY_MS)
    end
    if not entered then
        print(('^1[kora_multichar]^7 could not enter selection mode: %s')
            :format(tostring(enterErr or 'the server never answered')))
        return
    end
    currentMode = 'selection'
    SceneRuntime.beginMode()

    local fetched = bootCall('character list fetch', function()
        local list = Kora.callback.trigger('qb-multicharacter:server:setupCharacters')
        return type(list) == 'table' and list or nil
    end) or {}
    maxCharacters = Kora.callback.trigger('qb-multicharacter:server:GetNumberOfCharacters') or maxCharacters
    sceneCatalog = fetchSceneCatalog() or {}
    setCharacters(fetched)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(400)
    SetNuiFocus(true, true)
    send('multichar:show', {
        characters = characters,
        maxCharacters = maxCharacters,
        previewWatchdogMs = Config.previewWatchdogMs,
        ui = {
            combinedSelect = arrivalEnabled(),
            closeCreateOnBackdrop = Config.ui.closeCreateOnBackdrop,
            confirmDiscardOnClose = Config.ui.confirmDiscardOnClose,
            confirmDisconnect = Config.ui.confirmDisconnect,
            brandName = Config.ui.brandName,
            showNewSlotBadge = Config.ui.showNewSlotBadge,
            profile = Config.ui.profile,
            nationalities = Config.nationalities,
            defaultNationality = Config.defaultNationality,
            allowFreeTextNationality = Config.allowFreeTextNationality,
        },
    })
    if next(sceneCatalog) == nil then
        send('multichar:error', 'Scenes could not be loaded from the server. Previews will be unavailable.')
    end
end

RegisterNetEvent('qb-multicharacter:client:chooseChar', refreshCharacters)

local returningToSelection = false

local function returnToCharacterSelect()
    if returningToSelection or currentMode ~= nil then return end
    returningToSelection = true

    DoScreenFadeOut(250)
    local deadline = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end

    refreshCharacters()
    returningToSelection = false
end

RegisterNetEvent('qb-multicharacter:client:closeNUI', function()
    previewGeneration = previewGeneration + 1
    SceneRuntime.endMode()
    leaveServerMode()
    closeNuiOnly()
end)

RegisterNetEvent('qb-multicharacter:client:closeNUIdefault', function()
    pendingNewCharacter = true
    if arrivalEnabled() then
        -- A new character lands at the first arrival point, so they get the
        -- same flight as everyone else; there is no list to choose from.
        local first = Config.spawns and Config.spawns[1]
        local location = {
            id = 'first', label = 'First Arrival', coords = Config.defaultSpawn,
            preview = first and first.coords == Config.defaultSpawn and first.preview or nil,
        }
        selectedCharacter = nil
        local entered = Kora.callback.trigger('kora_multichar:server:enterMode', 'spawn')
        if entered then multicharSetClientMode('spawn', true) end
        multicharArrive(location, true)
        return
    end
    finishAt(Config.defaultSpawn)
end)

RegisterNetEvent('qb-multicharacter:client:spawnLastLocation', function(coords)
    finishAt(coords)
end)

-- Another player has just arrived near here; the server tells us what to play.
RegisterNetEvent('kora_multichar:client:arrivalEffect', function(asset, effect, scale, x, y, z)
    if currentMode ~= nil then return end
    SceneRuntime.playSyncedArrivalEffect(asset, effect, scale, x, y, z)
end)

RegisterNetEvent('multichar:client:selectFailed', function(err)
    if multicharPlayFailed then multicharPlayFailed() end
    send('multichar:error', err or 'Something went wrong.')
end)

RegisterNetEvent('kora_multichar:client:sceneUpsert', function(id, definition)
    local scene = SceneSchema.validate(id, definition, Config.sceneLimits)
    if not scene then return end
    sceneCatalog[id] = scene
    if currentMode == 'selection' and selectedCharacter then previewCharacter(selectedCharacter.citizenid) end
end)

RegisterNetEvent('kora_multichar:client:sceneRemove', function(id)
    sceneCatalog[id] = nil
    if currentMode == 'selection' and selectedCharacter then previewCharacter(selectedCharacter.citizenid) end
end)

RegisterNUICallback('multichar:preview', function(data, cb)
    local citizenid = type(data) == 'table' and data.citizenid
    if type(citizenid) ~= 'string' or not charactersById[citizenid] then
        send('multichar:previewReady', { ok = false, error = 'That character could not be previewed.' })
        cb({ ok = true })
        return
    end
    previewCharacter(citizenid)
    cb({ ok = true })
end)

RegisterNUICallback('multichar:createPreview', function(data, cb)
    previewGeneration = previewGeneration + 1
    local generation = previewGeneration
    local model = tonumber(data and data.gender) == 1 and 'mp_f_freemode_01' or 'mp_m_freemode_01'
    CreateThread(function()
        refetchScenesIfEmpty()
        if generation ~= previewGeneration then return end
        local called, ok, err = pcall(SceneRuntime.loadCharacter, sceneCatalog[Config.defaultScene], model, {})
        if not called then ok, err = false, tostring(ok) end
        if generation ~= previewGeneration or err == 'stale preview' then return end
        send('multichar:previewReady', { citizenid = 'new', scene = Config.defaultScene, ok = ok, error = err })
    end)
    cb({ ok = true })
end)

RegisterNUICallback('multichar:select', function(data, cb)
    local citizenid = type(data) == 'table' and data.citizenid
    if type(citizenid) ~= 'string' or not charactersById[citizenid] then cb({ ok = false }); return end
    TriggerServerEvent('qb-multicharacter:server:loadUserData', { citizenid = citizenid })
    cb({ ok = true })
end)

RegisterNUICallback('multichar:create', function(data, cb)
    if not nextFreeSlot(characters) then
        send('multichar:error', 'You have reached the maximum number of characters.')
        cb({ ok = false }); return
    end
    data = type(data) == 'table' and data or {}
    local nationalityOk, nationality = Kora.callback.trigger('kora_multichar:server:validateNationality', data.nationality)
    if not nationalityOk then
        send('multichar:error', type(nationality) == 'string' and nationality or 'Choose a valid nationality.')
        cb({ ok = false }); return
    end
    TriggerServerEvent('qb-multicharacter:server:createCharacter', {
        firstname = data.firstname,
        lastname = data.lastname,
        birthdate = data.birthdate,
        gender = tonumber(data.gender),
        nationality = nationality,
    })
    cb({ ok = true })
end)

RegisterNUICallback('multichar:delete', function(data, cb)
    local citizenid = type(data) == 'table' and data.citizenid
    if type(citizenid) ~= 'string' or not charactersById[citizenid] then cb({ ok = false }); return end
    local deleted, err = Kora.callback.trigger('qb-multicharacter:server:deleteCharacter', citizenid)
    if not deleted then
        send('multichar:error', err or 'Could not delete that character.')
        cb({ ok = false }); return
    end
    refreshCharacters()
    cb({ ok = true })
end)

RegisterNUICallback('multichar:disconnect', function(_, cb)
    TriggerServerEvent('qb-multicharacter:server:disconnect', 'Disconnected from character selection.')
    cb({ ok = true })
end)

local function awaitStablePlayerPed()
    while not NetworkIsSessionStarted() do Wait(0) end

    local deadline = GetGameTimer() + 30000
    local stableSince, lastPed = nil, nil
    while GetGameTimer() < deadline do
        local ped = PlayerPedId()
        if ped ~= 0 and DoesEntityExist(ped) and NetworkIsPlayerActive(PlayerId()) then
            if ped ~= lastPed then
                lastPed, stableSince = ped, GetGameTimer()
            elseif GetGameTimer() - stableSince >= 750 then
                return
            end
        else
            lastPed, stableSince = nil, nil
        end
        Wait(0)
    end
    print('^3[kora_multichar]^7 player ped never settled; opening selection anyway.')
end

local function whenServerIdReady(callback)
    local done = false
    local function try(serverId)
        if done or not serverId or serverId == -1 then return end
        done = true
        Kora.cache.offChange('serverId')
        CreateThread(function() callback(serverId) end)
    end
    local function watch()
        if done then return end
        Kora.cache.onChange('serverId', try)
        try(Kora.cache.serverId())
    end
    AddEventHandler('onClientResourceStart', function(resource)
        if resource == 'kora_lib' then watch() end
    end)
    watch()
end

CreateThread(function()
    awaitStablePlayerPed()
    whenServerIdReady(function(serverId)
        AddStateBagChangeHandler('kora_core:loggedIn', ('player:%s'):format(serverId), function(_, _, value)
            if value == false then CreateThread(returnToCharacterSelect) end
        end)
        if LocalPlayer.state['kora_core:loggedIn'] == true then return end
        TriggerEvent('qb-multicharacter:client:chooseChar')
    end)
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    previewGeneration = previewGeneration + 1
    currentMode = nil
    SetNuiFocus(false, false)
end)
