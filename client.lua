-- Character-select orchestration. The NUI owns presentation, SceneRuntime
-- owns the disposable world, and qbcore's legacy compatibility events remain
-- the only character lifecycle transport exposed to other resources.

local characters = {}
local charactersById = {}
local maxCharacters = 5
local sceneCatalog = {}
local selectedCharacter = nil
local previewGeneration = 0
local currentMode = nil

exports.qbcore:claimUI()

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

local function previewCharacter(citizenid)
    local character = charactersById[citizenid]
    if not character then return end
    selectedCharacter = character
    previewGeneration = previewGeneration + 1
    local generation = previewGeneration
    send('multichar:previewLoading', { citizenid = citizenid })

    CreateThread(function()
        local model, skin
        local ok = pcall(function()
            model, skin = QB.callback.trigger('qb-multicharacter:server:getSkin', citizenid)
        end)
        if generation ~= previewGeneration then return end
        if not ok or type(model) ~= 'string' then model, skin = fallbackModel(character), {} end
        local scene, sceneId = SceneSchema.resolve(sceneCatalog, character, Config.defaultScene)
        local loaded, err = SceneRuntime.loadCharacter(scene, model, skin)
        if not loaded and sceneId ~= Config.defaultScene then
            sceneId, scene = Config.defaultScene, sceneCatalog[Config.defaultScene]
            loaded, err = SceneRuntime.loadCharacter(scene, model, skin)
        end
        if not loaded then
            model, skin = fallbackModel(character), {}
            sceneId, scene = Config.defaultScene, sceneCatalog[Config.defaultScene]
            loaded, err = SceneRuntime.loadCharacter(scene, model, skin)
        end
        if generation ~= previewGeneration then return end
        send('multichar:previewReady', {
            citizenid = citizenid,
            scene = sceneId,
            ok = loaded == true,
            error = loaded and nil or err,
        })
    end)
end

local function leaveServerMode()
    local ok, result = pcall(function() return QB.callback.trigger('qbmultichar:server:leaveMode') end)
    return ok and result == true
end

local function closeNuiOnly()
    currentMode = nil
    SetNuiFocus(false, false)
    send('multichar:close')
end

-- Set on the new-character handoff and consumed by the next finishAt, so the
-- completion signal below can tell a brand-new character apart from an
-- ordinary login without every consumer having to infer it.
local pendingNewCharacter = false

-- The "you are actually in the world now" signal, for resources that must not
-- act until the player is spawned (qbclothing's first-character fitting room
-- is the reason this exists). Deliberately NOT the cleared `qbmultichar:mode`
-- state bag: leaveServerMode runs BEFORE the teleport below, and the bag clear
-- replicates asynchronously on top of that, so anything watching the bag can
-- wake while the ped is still being placed. This fires after the ped has been
-- moved, resurrected, revealed and unfrozen, and after the fade-in has
-- actually completed.
local function announceSpawnComplete(isNew)
    CreateThread(function()
        -- DoScreenFadeIn is asynchronous. Bounded, so a fade another resource
        -- cancels or overrides still releases the signal rather than stranding
        -- every listener for the rest of the session.
        local deadline = GetGameTimer() + 5000
        while not IsScreenFadedIn() and GetGameTimer() < deadline do Wait(0) end
        TriggerEvent('qbmultichar:client:spawnComplete', isNew == true)
    end)
end

local function finishAt(coords)
    local isNew = pendingNewCharacter
    pendingNewCharacter = false

    DoScreenFadeOut(250)
    local deadline = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
    SceneRuntime.endMode()
    leaveServerMode()
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

-- Shared with spawn.lua; one finalization path prevents cleanup differences
-- between fixed, last-location, and future house spawns.
function MulticharFinishSpawn(coords)
    finishAt(coords)
end

function MulticharSetClientMode(mode)
    currentMode = mode
end

local function refreshCharacters()
    local entered, enterErr = QB.callback.trigger('qbmultichar:server:enterMode', 'selection')
    if not entered then
        print(('[qbmultichar] could not enter selection mode: %s'):format(tostring(enterErr)))
        return
    end
    currentMode = 'selection'
    SceneRuntime.beginMode()

    local fetched = QB.callback.trigger('qb-multicharacter:server:setupCharacters') or {}
    maxCharacters = QB.callback.trigger('qb-multicharacter:server:GetNumberOfCharacters') or maxCharacters
    local fetchedScenes = QB.callback.trigger('qbmultichar:server:getScenes') or {}
    sceneCatalog = type(fetchedScenes) == 'table' and fetchedScenes or {}
    setCharacters(type(fetched) == 'table' and fetched or {})

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(400)
    SetNuiFocus(true, true)
    send('multichar:show', { characters = characters, maxCharacters = maxCharacters })
end

RegisterNetEvent('qb-multicharacter:client:chooseChar', refreshCharacters)

-- Returning to character select after a logout follows qbcore's replicated
-- login state instead of a private event. qbcore's logout only flushes the
-- character, clears `qbcore:loggedIn`, and fires its unload events -- it never
-- tells a character-select UI anything. Watching the state bag means EVERY
-- logout path lands here: qbmultichar's own /logout, an admin resource calling
-- the core export, or a delete that logs out a live handle.
--
-- Raw AddStateBagChangeHandler rather than QB.state.onChange, for the reason
-- fxmanifest.lua gives for the NUI natives: the qblib call registers the
-- handler inside qblib's own VM and relays every change back over a
-- cross-resource funcref. qbhud and qbclothing watch this same key the same way.
local returningToSelection = false

local function returnToCharacterSelect()
    -- currentMode is non-nil for the whole of selection, spawn, and the scene
    -- studio; those own the camera and the ped already, and the server refuses
    -- /logout during them. The flag covers the window before the enterMode
    -- callback returns, when currentMode is still nil.
    if returningToSelection or currentMode ~= nil then return end
    returningToSelection = true

    DoScreenFadeOut(250)
    local deadline = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end

    -- A ped logged out at the wheel would be hidden and frozen still seated,
    -- and would carry that vehicle into the next character's spawn.
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end

    refreshCharacters()
    returningToSelection = false
end

RegisterNetEvent('qb-multicharacter:client:closeNUI', function()
    SceneRuntime.endMode()
    leaveServerMode()
    closeNuiOnly()
end)

-- qbcore fires this only on successful character creation, so it is the one
-- place that knows the spawn about to run belongs to a brand-new character.
-- Both branches below end in finishAt, which consumes the flag.
RegisterNetEvent('qb-multicharacter:client:closeNUIdefault', function()
    pendingNewCharacter = true
    if type(MulticharOpenNewSpawn) == 'function' and MulticharOpenNewSpawn() then return end
    -- Defensive compatibility fallback if spawn.lua failed to initialize.
    finishAt(Config.defaultSpawn)
end)

RegisterNetEvent('qb-multicharacter:client:spawnLastLocation', function(coords)
    finishAt(coords)
end)

RegisterNetEvent('multichar:client:selectFailed', function(err)
    send('multichar:error', err or 'Something went wrong.')
end)

RegisterNetEvent('qbmultichar:client:sceneUpsert', function(id, definition)
    local scene = SceneSchema.validate(id, definition, Config.sceneLimits)
    if not scene then return end
    sceneCatalog[id] = scene
    if currentMode == 'selection' and selectedCharacter then previewCharacter(selectedCharacter.citizenid) end
end)

RegisterNetEvent('qbmultichar:client:sceneRemove', function(id)
    sceneCatalog[id] = nil
    if currentMode == 'selection' and selectedCharacter then previewCharacter(selectedCharacter.citizenid) end
end)

RegisterNUICallback('multichar:getTheme', function(_, cb)
    local ok, tokens = pcall(function() return QB.theme.tokens() end)
    cb(ok and tokens or {})
end)

RegisterNUICallback('multichar:preview', function(data, cb)
    local citizenid = type(data) == 'table' and data.citizenid
    if type(citizenid) == 'string' and charactersById[citizenid] then previewCharacter(citizenid) end
    cb({ ok = true })
end)

RegisterNUICallback('multichar:createPreview', function(data, cb)
    previewGeneration = previewGeneration + 1
    local generation = previewGeneration
    local model = tonumber(data and data.gender) == 1 and 'mp_f_freemode_01' or 'mp_m_freemode_01'
    local scene = sceneCatalog[Config.defaultScene]
    CreateThread(function()
        local ok, err = SceneRuntime.loadCharacter(scene, model, {})
        if generation ~= previewGeneration then return end
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
    TriggerServerEvent('qb-multicharacter:server:createCharacter', {
        firstname = data.firstname,
        lastname = data.lastname,
        birthdate = data.birthdate,
        gender = tonumber(data.gender),
        nationality = data.nationality,
    })
    cb({ ok = true })
end)

RegisterNUICallback('multichar:delete', function(data, cb)
    local citizenid = type(data) == 'table' and data.citizenid
    if type(citizenid) ~= 'string' or not charactersById[citizenid] then cb({ ok = false }); return end
    local deleted, err = QB.callback.trigger('qb-multicharacter:server:deleteCharacter', citizenid)
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

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(0) end
    local serverId = QB.cache.serverId()
    while not serverId or serverId == -1 do
        Wait(0)
        serverId = QB.cache.serverId()
    end
    -- Registered here, not at file scope: the bag name needs a real server id,
    -- which only exists once the session has started.
    AddStateBagChangeHandler('qbcore:loggedIn', ('player:%s'):format(serverId), function(_, _, value)
        -- State-bag handlers must not yield; returnToCharacterSelect waits on
        -- the fade and on server callbacks.
        if value == false then CreateThread(returnToCharacterSelect) end
    end)
    TriggerEvent('qb-multicharacter:client:chooseChar')
end)

CreateThread(function()
    local ok, tokens = pcall(function() return QB.theme.tokens() end)
    if ok then send('multichar:theme', tokens) end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    previewGeneration = previewGeneration + 1
    currentMode = nil
    SetNuiFocus(false, false)
end)
