-- Character-select orchestration. The NUI owns presentation, SceneRuntime
-- owns the disposable world, and kora_core's legacy compatibility events remain
-- the only character lifecycle transport exposed to other resources.

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

-- Character select boots on a client that is at its coldest, and every step of
-- it is a cross-resource callback with a bounded timeout. A machine that takes
-- a long time to join can blow through that timeout while the server is
-- answering perfectly well, and a rejected round trip is indistinguishable at
-- the call site from a refusal: it just comes back nil. Previously that meant
-- one printed line and a player left staring at a frozen, invisible ped with
-- no UI -- or, worse, an empty scene catalog, which makes EVERY preview fail
-- with 'no matching scene'. That is what "scenes aren't loading" looks like
-- from the player's side, and nothing on screen said so.
--
-- So every boot callback retries, and every give-up says which step died.
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
            print(('^3[qbmultichar]^7 %s did not answer (attempt %d/%d) -- retrying in %dms')
                :format(label, tries, attempts, BOOT_RETRY_MS))
            Wait(BOOT_RETRY_MS)
        end
    end
    print(('^1[qbmultichar]^7 %s never answered after %d attempt(s).'):format(label, attempts))
    return nil
end

---@param attempts integer|nil
local function fetchSceneCatalog(attempts)
    -- An empty table is treated as no answer, not as an empty registry: the
    -- server registers the bundled scenes at script load, so zero scenes on the
    -- wire means the round trip failed, not that this server has none.
    return bootCall('scene catalog fetch', function()
        local fetched = QB.callback.trigger('qbmultichar:server:getScenes')
        if type(fetched) ~= 'table' or next(fetched) == nil then return nil end
        return fetched
    end, attempts)
end

-- One attempt, never the full boot budget: this runs with the player already
-- watching a "Loading scene..." spinner, so it must either recover promptly or
-- get out of the way and let the preview report its own failure.
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
        local model, skin = QB.callback.trigger('qb-multicharacter:server:getSkin', citizenid)
        if generation ~= previewGeneration then return end
        if type(model) ~= 'string' then model, skin = fallbackModel(character), {} end
        -- A catalog that arrived empty (a boot fetch that never answered) makes
        -- all three attempts below fail identically with 'no matching scene'.
        -- One late refetch recovers a client whose network settled after boot.
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
    return QB.callback.trigger('qbmultichar:server:leaveMode') == true
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
-- act until the player is spawned (kora_clothing's first-character fitting room
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
    previewGeneration = previewGeneration + 1
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
function multicharFinishSpawn(coords)
    finishAt(coords)
end

function multicharSetClientMode(mode)
    previewGeneration = previewGeneration + 1
    currentMode = mode
end

local function refreshCharacters()
    previewGeneration = previewGeneration + 1
    local entered, enterErr
    for tries = 1, BOOT_MAX_ATTEMPTS do
        entered, enterErr = QB.callback.trigger('qbmultichar:server:enterMode', 'selection')
        -- An explicit `false` is a real refusal with a reason ('already logged
        -- in') and must not be retried. Only nil -- the shape a rejected or
        -- timed-out round trip takes -- means "ask again".
        if entered ~= nil then break end
        print(('^3[qbmultichar]^7 selection handshake did not answer (attempt %d/%d) -- retrying in %dms')
            :format(tries, BOOT_MAX_ATTEMPTS, BOOT_RETRY_MS))
        Wait(BOOT_RETRY_MS)
    end
    if not entered then
        print(('^1[qbmultichar]^7 could not enter selection mode: %s')
            :format(tostring(enterErr or 'the server never answered')))
        return
    end
    currentMode = 'selection'
    SceneRuntime.beginMode()

    local fetched = bootCall('character list fetch', function()
        local list = QB.callback.trigger('qb-multicharacter:server:setupCharacters')
        return type(list) == 'table' and list or nil
    end) or {}
    maxCharacters = QB.callback.trigger('qb-multicharacter:server:GetNumberOfCharacters') or maxCharacters
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
            closeCreateOnBackdrop = Config.ui.closeCreateOnBackdrop,
            confirmDiscardOnClose = Config.ui.confirmDiscardOnClose,
        },
    })
    -- Say it on screen rather than letting the player sit on "Loading scene..."
    -- forever while every preview quietly fails to resolve a scene.
    if next(sceneCatalog) == nil then
        send('multichar:error', 'Scenes could not be loaded from the server. Previews will be unavailable.')
    end
end

RegisterNetEvent('qb-multicharacter:client:chooseChar', refreshCharacters)

-- Returning to character select after a logout follows kora_core's replicated
-- login state instead of a private event. kora_core's logout only flushes the
-- character, clears `qbcore:loggedIn`, and fires its unload events -- it never
-- tells a character-select UI anything. Watching the state bag means EVERY
-- logout path lands here: kora_multichar's own /logout, an admin resource calling
-- the core export, or a delete that logs out a live handle.
--
-- Raw AddStateBagChangeHandler rather than QB.state.onChange, for the reason
-- fxmanifest.lua gives for the NUI natives: the kora_lib call registers the
-- handler inside kora_lib's own VM and relays every change back over a
-- cross-resource funcref. kora_hud and kora_clothing watch this same key the same way.
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
    previewGeneration = previewGeneration + 1
    SceneRuntime.endMode()
    leaveServerMode()
    closeNuiOnly()
end)

-- kora_core fires this only on successful character creation, so it is the one
-- place that knows the spawn about to run belongs to a brand-new character.
-- A new character has no saved location to choose from: land at the configured
-- first-arrival point immediately. In particular, do not open the cinematic
-- spawn picker here -- its preview is optional for returning players but must
-- never be able to hold up a newly created character's first spawn.
RegisterNetEvent('qb-multicharacter:client:closeNUIdefault', function()
    pendingNewCharacter = true
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

RegisterNUICallback('multichar:preview', function(data, cb)
    local citizenid = type(data) == 'table' and data.citizenid
    if type(citizenid) ~= 'string' or not charactersById[citizenid] then
        -- Answer anyway so the NUI never waits on a preview that will not come.
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
        -- pcall: a throw here would end the thread without a reply, and the
        -- NUI would wait on a preview that never comes.
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

-- NetworkIsSessionStarted is true well before the game has finished putting the
-- player in the world: spawnmanager's own first spawn is often still in flight,
-- and completing it replaces the player ped with a fresh, visible, unfrozen
-- handle. Opening selection into that window is what made the FIRST preview of
-- a session behave differently from every later one. Wait for a ped that
-- actually exists and stays the same handle for a moment, so the cinematic
-- setup applies to the real player rather than to a placeholder the engine is
-- about to throw away. Bounded: a client that never settles still gets its
-- character select, just with the old racy behaviour rather than none at all.
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
    print('^3[qbmultichar]^7 player ped never settled; opening selection anyway.')
end

CreateThread(function()
    awaitStablePlayerPed()
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

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    previewGeneration = previewGeneration + 1
    currentMode = nil
    SetNuiFocus(false, false)
end)
