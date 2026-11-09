SceneRuntime = SceneRuntime or {}

local pendingAssets = {}

local state = {
    modeActive = false,
    sceneGeneration = 0,
    timelineGeneration = 0,
    entities = {},
    definitions = {},
    cameras = {},
    cameraDefinitions = {},
    particles = {},
    animAssets = {},
    ptfxAssets = {},
    sounds = {},
    previewPed = nil,
    hiddenPed = nil,
    activeCam = nil,
    spawnLookAt = nil,
    spawnPosition = nil,
    playerState = nil,
    scene = nil,
}

local function entityExists(entity)
    return entity and entity ~= 0 and DoesEntityExist(entity)
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelValid(hash) then return nil end
    local loaded = Kora.stream.loadModel(hash, nil, {
        timeout = Config.sceneLimits.streamTimeoutMs,
    })
    return loaded or nil
end

local function loadSceneAsset(group, name, loader, hasLoaded, release)
    local assets = state[group]
    local asset = assets[name]
    if not asset then
        asset = { pending = 0, owned = false, name = name, release = release }
        assets[name] = asset
    end
    local requested = not hasLoaded(name)
    if requested then asset.requested = true end
    asset.pending = asset.pending + 1
    pendingAssets[asset] = true
    local ok, loaded = pcall(loader, name, nil, { timeout = Config.sceneLimits.streamTimeoutMs })
    asset.pending = asset.pending - 1
    if asset.pending == 0 then pendingAssets[asset] = nil end
    if ok and loaded ~= false and requested and not asset.released then asset.owned = true end
    if assets ~= state[group] and asset.pending == 0 and asset.owned then
        asset.owned = false
        local current = state[group][name]
        if current then current.owned = true else release(name) end
    end
    return ok and loaded ~= false and assets == state[group]
end

local function releaseSceneAssets(assets, release)
    for name, asset in pairs(assets) do
        if asset.pending == 0 and asset.owned then
            release(name)
            asset.owned = false
        end
    end
end

local function loadAnim(dict)
    if type(dict) ~= 'string' or dict == '' then return false end
    return loadSceneAsset('animAssets', dict, Kora.stream.loadAnimDict, HasAnimDictLoaded, RemoveAnimDict)
end

local function localWorld(scene, offset)
    return SceneSchema.localToWorld(scene.anchor, offset)
end

local function snapToGround(coords)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    for _, height in ipairs({ 2.0, 10.0, 50.0 }) do
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + height, false)
        if found and math.abs(groundZ - coords.z) <= 8.0 then
            return { x = coords.x, y = coords.y, z = groundZ + 0.025, w = coords.w }
        end
    end
    return coords
end

local function snapToWater(coords)
    local found, waterZ = GetWaterHeight(coords.x, coords.y, coords.z + 5.0)
    if found then return { x = coords.x, y = coords.y, z = waterZ + 0.08, w = coords.w } end
    return coords
end

local FADE_OUT_WAIT_MS = 350

local function fadeWorldOut(generation)
    if not IsScreenFadedOut() then DoScreenFadeOut(120) end
    local deadline = GetGameTimer() + FADE_OUT_WAIT_MS
    while generation == state.sceneGeneration and not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
    return generation == state.sceneGeneration
end

local function revealWorld(generation)
    if generation == state.sceneGeneration then DoScreenFadeIn(350) end
end

local STREAM_START_RETRY_MS = 250
local STREAM_START_WINDOW_MS = 1000

local function requestLoadScene(coords)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    return NewLoadSceneStartSphere(coords.x, coords.y, coords.z, 100.0, 0) == true
end

---Parks the hidden player ped on the preview point so the streamer has a real
---anchor there.
---@param coords table
local function anchorPlayerAt(coords)
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end

    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityVisible(ped, false, false)
    SetFocusEntity(ped)
end

---Streams the world at `coords`.
---
---Returns `current` (this preview is still the live one) and `accepted` (the
---area is worth showing). `accepted` now means collision actually loaded around
---the anchor, which is the thing a camera needs, rather than whether the engine
---deigned to accept a load-scene request.
---@param coords table
---@param generation integer
---@return boolean current
---@return boolean accepted
local function streamWorld(coords, generation)
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    anchorPlayerAt(coords)

    local started = requestLoadScene(coords)
    local retryWindow = GetGameTimer() + STREAM_START_WINDOW_MS
    while not started and generation == state.sceneGeneration and GetGameTimer() < retryWindow do
        Wait(STREAM_START_RETRY_MS)
        started = requestLoadScene(coords)
    end

    local ped = PlayerPedId()
    local deadline = GetGameTimer() + Config.sceneLimits.worldStreamTimeoutMs
    local loaded = false

    while generation == state.sceneGeneration and GetGameTimer() < deadline do
        if HasCollisionLoadedAroundEntity(ped) or (started and IsNewLoadSceneLoaded()) then
            loaded = true
            break
        end
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end

    if generation ~= state.sceneGeneration then return false, false end
    if IsNewLoadSceneActive() then NewLoadSceneStop() end

    return true, true, loaded
end

local function applyFallbackSkin(ped, skin)
    if type(skin) ~= 'table' then return end
    for key, entry in pairs(type(skin.components) == 'table' and skin.components or {}) do
        local id, drawable, texture = tonumber(key), tonumber(entry.d), tonumber(entry.t) or 0
        if id and drawable and drawable >= 0 and drawable < GetNumberOfPedDrawableVariations(ped, id) then
            local textures = GetNumberOfPedTextureVariations(ped, id, drawable)
            if texture < 0 or texture >= textures then texture = 0 end
            SetPedComponentVariation(ped, id, drawable, texture, 0)
        end
    end
    for key, entry in pairs(type(skin.props) == 'table' and skin.props or {}) do
        local id, drawable, texture = tonumber(key), tonumber(entry.d), tonumber(entry.t) or 0
        if id and drawable and drawable >= 0 and drawable < GetNumberOfPedPropDrawableVariations(ped, id) then
            local textures = GetNumberOfPedPropTextureVariations(ped, id, drawable)
            if texture < 0 or texture >= textures then texture = 0 end
            SetPedPropIndex(ped, id, drawable, texture, true)
        elseif id then
            ClearPedProp(ped, id)
        end
    end
end

local function applyAppearance(ped, model, skin)
    if GetResourceState('kora_clothing') == 'started' then
        local ok, applied = pcall(function() return exports.kora_clothing:ApplyAppearanceToPed(ped, model, skin or {}) end)
        if ok and applied == true then return end
    end
    applyFallbackSkin(ped, skin)
end

local function applyIdle(ped, definition)
    if not entityExists(ped) then return end
    if definition.scenario then
        TaskStartScenarioInPlace(ped, definition.scenario, 0, true)
    elseif definition.animation and loadAnim(definition.animation.dict) then
        if not entityExists(ped) then return end
        TaskPlayAnim(ped, definition.animation.dict, definition.animation.name, 4.0, -4.0, -1,
            definition.animation.flag or 1, 0.0, false, false, false)
    end
end

local function applyVehicleState(vehicle, values)
    if not entityExists(vehicle) then return end
    values = values or {}
    if values.engine ~= nil then SetVehicleEngineOn(vehicle, values.engine, true, false) end
    if values.lights ~= nil then SetVehicleLights(vehicle, values.lights and 2 or 1) end
    if values.siren ~= nil then SetVehicleSiren(vehicle, values.siren) end
    if values.mutedSiren ~= nil then SetVehicleHasMutedSirens(vehicle, values.mutedSiren) end
    if values.anchored ~= nil then SetBoatAnchor(vehicle, values.anchored) end
    if values.livery ~= nil then SetVehicleLivery(vehicle, tonumber(values.livery) or 0) end
    if values.primaryColor ~= nil or values.secondaryColor ~= nil then
        local primary, secondary = GetVehicleColours(vehicle)
        SetVehicleColours(vehicle, tonumber(values.primaryColor) or primary, tonumber(values.secondaryColor) or secondary)
    end
    for extra, enabled in pairs(values.extras or {}) do
        local extraId = tonumber(extra)
        if extraId and DoesExtraExist(vehicle, extraId) then SetVehicleExtra(vehicle, extraId, not enabled) end
    end
    for door, open in pairs(values.doors or {}) do
        local doorId = tonumber(door)
        if doorId then
            if open then SetVehicleDoorOpen(vehicle, doorId, false, false) else SetVehicleDoorShut(vehicle, doorId, false) end
        end
    end
end

local function createSceneEntity(scene, definition, generation)
    local hash = loadModel(definition.model)
    if not hash then return nil end
    if generation ~= state.sceneGeneration then SetModelAsNoLongerNeeded(hash); return nil, true end
    local coords = localWorld(scene, definition.offset)
    if definition.snapToWater == true then
        coords = snapToWater(coords)
    elseif definition.type ~= 'prop' and definition.snapToGround ~= false then
        coords = snapToGround(coords)
    end
    local entity
    if definition.type == 'ped' then
        entity = CreatePed(4, hash, coords.x, coords.y, coords.z, coords.w, false, false)
    elseif definition.type == 'vehicle' then
        entity = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w, false, false)
    else
        entity = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(entity, coords.w)
    end
    SetModelAsNoLongerNeeded(hash)
    if not entityExists(entity) then return nil end
    SetEntityAsMissionEntity(entity, true, true)
    SetEntityInvincible(entity, true)
    SetEntityCollision(entity, definition.collision == true, definition.collision == true)
    FreezeEntityPosition(entity, definition.frozen ~= false)
    if definition.type == 'ped' then
        SetBlockingOfNonTemporaryEvents(entity, true)
        if not definition.seat then applyIdle(entity, definition) end
    elseif definition.type == 'vehicle' then
        if definition.snapToWater ~= true then SetVehicleOnGroundProperly(entity) end
        applyVehicleState(entity, definition.vehicle)
    end
    if generation ~= state.sceneGeneration then
        if entityExists(entity) then DeleteEntity(entity) end
        return nil, true
    end
    return entity
end

local function seatScenePeds(scene)
    for _, definition in ipairs(scene.entities or {}) do
        if definition.type == 'ped' and definition.seat then
            local ped, vehicle = state.entities[definition.id], state.entities[definition.seat.vehicle]
            if entityExists(ped) and entityExists(vehicle) then
                ClearPedTasksImmediately(ped)
                FreezeEntityPosition(ped, false)
                SetPedIntoVehicle(ped, vehicle, definition.seat.index)
                SetPedCanBeDraggedOut(ped, false)
                SetPedKeepTask(ped, true)
            end
        end
    end
end

local function stopParticle(handle)
    if handle and handle ~= 0 then StopParticleFxLooped(handle, false) end
end

local function cleanupScene()
    state.timelineGeneration = state.timelineGeneration + 1
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    for _, sound in ipairs(state.sounds) do
        StopSound(sound)
        ReleaseSoundId(sound)
    end
    for _, particle in ipairs(state.particles) do stopParticle(particle) end
    for _, cam in pairs(state.cameras) do
        if DoesCamExist(cam) then DestroyCam(cam, false) end
    end
    for _, entity in pairs(state.entities) do
        if entityExists(entity) then DeleteEntity(entity) end
    end
    if entityExists(state.previewPed) then DeleteEntity(state.previewPed) end
    releaseSceneAssets(state.animAssets, RemoveAnimDict)
    releaseSceneAssets(state.ptfxAssets, RemoveNamedPtfxAsset)
    state.animAssets, state.ptfxAssets = {}, {}
    state.entities, state.definitions, state.cameras, state.cameraDefinitions = {}, {}, {}, {}
    state.particles, state.sounds = {}, {}
    state.previewPed, state.activeCam, state.scene = nil, nil, nil
    state.spawnLookAt, state.spawnPosition = nil, nil
    RenderScriptCams(false, true, 350, true, true)
    ClearFocus()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    NetworkClearClockTimeOverride()
    ClearTimecycleModifier()
end

local function failLoad(generation, message)
    if generation == state.sceneGeneration then cleanupScene() end
    return false, message
end

---Tells the NUI the spawn camera is live and looking at the place, so the
---"Scouting your arrival" cover can come down.
---
---Sent SEPARATELY from previewSpawn's return value, and that is the whole
---point. The focus callback only answers once the entire preview has settled,
---and the NUI has to race a timeout against it derived from the real worst
---case (see spawnPreviewBudgetMs -- over a minute). Releasing the cover on
---that answer meant a slow world stream sat the player on a loading panel for
---the full budget with a finished camera behind it. The cover now lasts exactly
---as long as there is genuinely nothing to look at.
---@param generation integer The scene generation this preview belongs to.
local function announcePreviewLive(generation)
    if generation ~= state.sceneGeneration then return end
    SendNUIMessage({ action = 'multichar:spawn:previewLive', data = { generation = generation } })
end

---Progress note while the streamer works, so a long load reads as busy rather
---than frozen. Purely cosmetic -- it changes no state on either side.
---@param generation integer
---@param stage string
local function announcePreviewStage(generation, stage)
    if generation ~= state.sceneGeneration then return end
    SendNUIMessage({ action = 'multichar:spawn:previewStage', data = { stage = stage } })
end

local CAMERA_TRACE_FLAGS = 273
local CAMERA_TRACE_RADIUS = 0.28
local CAMERA_FAN_ANGLES = { 0.0, 28.0, -28.0, 55.0, -55.0, 82.0, -82.0, 180.0 }

local function traceCameraPath(subject, candidate, ignoreEntity)
    local handle = StartShapeTestCapsule(
        subject.x, subject.y, subject.z,
        candidate.x, candidate.y, candidate.z,
        CAMERA_TRACE_RADIUS, CAMERA_TRACE_FLAGS, ignoreEntity or 0, 7
    )
    if not handle or handle == 0 then return nil end

    local deadline = GetGameTimer() + 250
    repeat
        local status, hit, impact = GetShapeTestResult(handle)
        if status == 2 then return hit == true or hit == 1, impact end
        if status == 0 then return nil end
        Wait(0)
    until GetGameTimer() >= deadline
    return nil
end

local function rotateCameraCandidate(position, subject, angle, lift)
    local radians = math.rad(angle)
    local cosA, sinA = math.cos(radians), math.sin(radians)
    local dx, dy = position.x - subject.x, position.y - subject.y
    return vector3(
        subject.x + dx * cosA - dy * sinA,
        subject.y + dx * sinA + dy * cosA,
        position.z + (lift or 0.0)
    )
end

local function resolveCameraPosition(position, subject, ignoreEntity, secondarySubject)
    local firstImpact, firstImpactOrigin
    for index, angle in ipairs(CAMERA_FAN_ANGLES) do
        local lift = index > 5 and 0.65 or 0.0
        local candidate = rotateCameraCandidate(position, subject, angle, lift)
        local blocked, impact = traceCameraPath(subject, candidate, ignoreEntity)
        if blocked == false and secondarySubject then
            local secondaryBlocked, secondaryImpact = traceCameraPath(secondarySubject, candidate, ignoreEntity)
            blocked, impact = secondaryBlocked, secondaryImpact
            if secondaryBlocked and not firstImpact then firstImpact, firstImpactOrigin = secondaryImpact, secondarySubject end
        end
        if blocked == false then return candidate end
        if blocked and not firstImpact then firstImpact, firstImpactOrigin = impact, subject end
    end

    if firstImpact then
        local origin = firstImpactOrigin or subject
        local dx, dy, dz = firstImpact.x - origin.x, firstImpact.y - origin.y, firstImpact.z - origin.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        if distance > 1.25 then
            local usable = distance - 0.55
            return vector3(
                origin.x + dx / distance * usable,
                origin.y + dy / distance * usable,
                origin.z + dz / distance * usable
            )
        end
    end

    return position
end

local function createCamera(scene, definition, generation)
    local position, lookAt = localWorld(scene, definition.offset), localWorld(scene, definition.lookAt)
    local characterOffset = scene.character.offset
    local characterLookAt = localWorld(scene, {
        x = characterOffset.x,
        y = characterOffset.y,
        z = characterOffset.z + 1.15,
    })
    position = resolveCameraPosition(position, lookAt, state.previewPed, characterLookAt)
    if generation ~= state.sceneGeneration then return nil, true end
    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    if not camera or camera == 0 or not DoesCamExist(camera) then return nil end
    SetCamCoord(camera, position.x, position.y, position.z)
    PointCamAtCoord(camera, lookAt.x, lookAt.y, lookAt.z)
    SetCamFov(camera, definition.fov or 38.0)
    if definition.dof then
        SetCamUseShallowDofMode(camera, true)
        SetCamNearDof(camera, definition.dof.near or 1.0)
        SetCamFarDof(camera, definition.dof.far or 4.0)
        SetCamDofStrength(camera, definition.dof.strength or 0.5)
    end
    return camera
end

local function activateCamera(id, transitionMs)
    local nextCam = state.cameras[id]
    if not nextCam then return end
    transitionMs = transitionMs or (state.cameraDefinitions[id] and state.cameraDefinitions[id].transitionMs)
    if state.activeCam and state.activeCam ~= nextCam then
        SetCamActiveWithInterp(nextCam, state.activeCam, transitionMs or 900, true, true)
    else
        SetCamActive(nextCam, true)
        RenderScriptCams(true, true, transitionMs or 350, true, true)
    end
    state.activeCam = nextCam
end

local function playParticle(cue)
    if type(cue.asset) ~= 'string' or type(cue.effect) ~= 'string' then return end
    local generation = state.timelineGeneration
    if not loadSceneAsset('ptfxAssets', cue.asset, Kora.stream.loadPtfx,
        HasNamedPtfxAssetLoaded, RemoveNamedPtfxAsset) then return end
    if generation ~= state.timelineGeneration then return end
    UseParticleFxAssetNextCall(cue.asset)
    local target = cue.target == 'character' and state.previewPed or state.entities[cue.target]
    if cue.target and not entityExists(target) then return end
    local handle
    if entityExists(target) then
        handle = StartParticleFxLoopedOnEntity(cue.effect, target, 0.0, 0.0, cue.z or 0.5,
            0.0, 0.0, 0.0, cue.scale or 1.0, false, false, false)
    elseif state.scene then
        local coords = localWorld(state.scene, cue.offset or { x = 0.0, y = 0.0, z = 0.0 })
        handle = StartParticleFxLoopedAtCoord(cue.effect, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0,
            cue.scale or 1.0, false, false, false, false)
    end
    if handle and handle ~= 0 then
        state.particles[#state.particles + 1] = handle
        if cue.durationMs then SetTimeout(cue.durationMs, function()
            if generation == state.timelineGeneration then stopParticle(handle) end
        end) end
    end
end

local function driveVehicleRoute(cue, driver)
    if not entityExists(driver) or not state.scene then return end
    local vehicle = GetVehiclePedIsIn(driver, false)
    if not entityExists(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= driver then return end
    local destination = localWorld(state.scene, cue.destination)
    if cue.snapToWater == true then destination = snapToWater(destination)
    elseif cue.snapToGround ~= false then destination = snapToGround(destination) end
    FreezeEntityPosition(vehicle, false)
    SetEntityCollision(vehicle, true, true)
    if cue.snapToWater == true then SetBoatAnchor(vehicle, false) end
    SetVehicleEngineOn(vehicle, true, true, false)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.0)
    SetPedKeepTask(driver, true)
    if cue.snapToWater == true then
        TaskBoatMission(
            driver, vehicle, 0, 0, destination.x, destination.y, destination.z,
            4, cue.speed or 11.0, cue.drivingStyle or 786603, cue.stoppingRange or 5.0, 0
        )
    else
        TaskVehicleDriveToCoordLongrange(
            driver, vehicle, destination.x, destination.y, destination.z,
            cue.speed or 11.0, cue.drivingStyle or 786603, cue.stoppingRange or 5.0
        )
    end
end

local function playCue(cue)
    if cue.type == 'camera' then
        activateCamera(cue.camera, cue.transitionMs)
        return
    end
    local target = cue.target == 'character' and state.previewPed or state.entities[cue.target]
    if cue.type == 'animation' and entityExists(target) then
        if cue.stop then ClearPedTasks(target)
        elseif loadAnim(cue.dict) and entityExists(target) then TaskPlayAnim(target, cue.dict, cue.name, 4.0, -4.0, cue.durationMs or -1, cue.flag or 1, 0.0, false, false, false) end
    elseif cue.type == 'scenario' and entityExists(target) then
        ClearPedTasks(target)
        if cue.name then TaskStartScenarioInPlace(target, cue.name, 0, true) end
    elseif cue.type == 'vehicleState' then
        applyVehicleState(target, cue)
    elseif cue.type == 'entityVisibility' and entityExists(target) then
        SetEntityVisible(target, cue.visible ~= false, false)
    elseif cue.type == 'vehicleRoute' then
        driveVehicleRoute(cue, target)
    elseif cue.type == 'particle' then
        playParticle(cue)
    elseif cue.type == 'nativeSound' and type(cue.name) == 'string' then
        if cue.target and not entityExists(target) then return end
        local sound = GetSoundId()
        if entityExists(target) then
            PlaySoundFromEntity(sound, cue.name, target, cue.set or 'HUD_FRONTEND_DEFAULT_SOUNDSET', true, 0)
        elseif state.scene then
            local coords = localWorld(state.scene, cue.offset or { x = 0.0, y = 0.0, z = 0.0 })
            PlaySoundFromCoord(sound, cue.name, coords.x, coords.y, coords.z, cue.set or 'HUD_FRONTEND_DEFAULT_SOUNDSET', true, 0, false)
        end
        state.sounds[#state.sounds + 1] = sound
    end
end

local function startTimeline(scene)
    local timeline = scene.timeline or {}
    local cues = timeline.cues or {}
    if Config.cameraMode ~= 'cycle' then
        local kept = {}
        for _, cue in ipairs(cues) do
            if cue.type ~= 'camera' then kept[#kept + 1] = cue end
        end
        cues = kept
    end
    if #cues == 0 or (timeline.durationMs or 0) <= 0 then return end
    state.timelineGeneration = state.timelineGeneration + 1
    local generation = state.timelineGeneration
    CreateThread(function()
        repeat
            local started, index = GetGameTimer(), 1
            while generation == state.timelineGeneration and GetGameTimer() - started <= timeline.durationMs do
                local elapsed = GetGameTimer() - started
                while generation == state.timelineGeneration and cues[index] and (cues[index].at or 0) <= elapsed do
                    playCue(cues[index]); index = index + 1
                end
                Wait(0)
            end
        until generation ~= state.timelineGeneration or timeline.loop ~= true
    end)
end

local function applyEnvironment(environment)
    environment = environment or {}
    if environment.hour ~= nil then NetworkOverrideClockTime(environment.hour, environment.minute or 0, 0) end
    if environment.weather then
        SetWeatherTypeNow(environment.weather)
        SetWeatherTypeNowPersist(environment.weather)
    end
    if environment.timecycle then
        SetTimecycleModifier(environment.timecycle)
        SetTimecycleModifierStrength(environment.strength or 0.25)
    end
end

local function hidePlayerPed(ped)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityVisible(ped, false, false)
end

function SceneRuntime.beginMode()
    if state.modeActive then return end
    state.modeActive = true
    local ped = PlayerPedId()
    state.playerState = {
        visible = IsEntityVisible(ped),
        invincible = GetPlayerInvincible(Kora.cache.playerId()),
        frozen = IsEntityPositionFrozen(ped),
        coords = GetEntityCoords(ped),
        heading = GetEntityHeading(ped),
    }
    hidePlayerPed(ped)
    state.hiddenPed = ped
    DoScreenFadeOut(0)

    -- Ped swaps are picked up from the shared kora_lib cache instead of polling
    -- PlayerPedId() every frame; the screen is faded out so the cache interval is invisible.
    Kora.cache.onChange('ped', function(newPed)
        if state.modeActive and newPed ~= state.hiddenPed then
            hidePlayerPed(newPed)
            state.hiddenPed = newPed
        end
    end)

    -- Only the natives that genuinely need re-asserting every frame stay in the loop.
    local hideHud, disableControls = HideHudAndRadarThisFrame, DisableAllControlActions
    local pedDensity, scenarioDensity = SetPedDensityMultiplierThisFrame, SetScenarioPedDensityMultiplierThisFrame
    local vehDensity, randomVehDensity = SetVehicleDensityMultiplierThisFrame, SetRandomVehicleDensityMultiplierThisFrame
    local parkedDensity = SetParkedVehicleDensityMultiplierThisFrame

    CreateThread(function()
        while state.modeActive do
            hideHud()
            disableControls(0)
            pedDensity(0.0)
            scenarioDensity(0.0, 0.0)
            vehDensity(0.0)
            randomVehDensity(0.0)
            parkedDensity(0.0)
            Wait(0)
        end
    end)
end

function SceneRuntime.loadCharacter(scene, model, skin)
    state.sceneGeneration = state.sceneGeneration + 1
    local generation = state.sceneGeneration
    if not fadeWorldOut(generation) then return false, 'stale preview' end
    cleanupScene()
    if not scene then return failLoad(generation, 'no matching scene') end
    state.scene = scene
    applyEnvironment(scene.environment)
    if not streamWorld(scene.anchor, generation) then return false, 'stale preview' end

    local groundedAnchor = snapToGround(scene.anchor)
    if math.abs(groundedAnchor.z - scene.anchor.z) > 0.001 then
        scene = SceneSchema.clone(scene)
        scene.anchor = { x = scene.anchor.x, y = scene.anchor.y, z = groundedAnchor.z, w = scene.anchor.w }
        state.scene = scene
    end

    local hash = loadModel(model)
    if generation ~= state.sceneGeneration then
        if hash then SetModelAsNoLongerNeeded(hash) end
        return false, 'stale preview'
    end
    if not hash then return failLoad(generation, 'character model could not be loaded') end
    local charCoords = snapToGround(localWorld(scene, scene.character.offset))
    state.previewPed = CreatePed(4, hash, charCoords.x, charCoords.y, charCoords.z, charCoords.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not entityExists(state.previewPed) then return failLoad(generation, 'character preview could not be created') end
    SetEntityAsMissionEntity(state.previewPed, true, true)
    SetEntityInvincible(state.previewPed, true)
    SetEntityCollision(state.previewPed, false, false)
    FreezeEntityPosition(state.previewPed, true)
    SetBlockingOfNonTemporaryEvents(state.previewPed, true)
    applyAppearance(state.previewPed, model, skin)
    applyIdle(state.previewPed, scene.character)

    for _, definition in ipairs(scene.entities or {}) do
        if generation ~= state.sceneGeneration then return false, 'stale preview' end
        local entity, stale = createSceneEntity(scene, definition, generation)
        if stale then return false, 'stale preview' end
        if entity then state.entities[definition.id], state.definitions[definition.id] = entity, definition end
    end
    seatScenePeds(scene)
    for _, definition in ipairs(scene.cameras or {}) do
        local camera, stale = createCamera(scene, definition, generation)
        if stale then return false, 'stale preview' end
        if camera then state.cameras[definition.id], state.cameraDefinitions[definition.id] = camera, definition end
    end
    local first
    for _, definition in ipairs(scene.cameras or {}) do
        if state.cameras[definition.id] then first = definition; break end
    end
    if not first then return failLoad(generation, 'scene has no usable camera') end
    activateCamera(first.id, 350)
    startTimeline(scene)
    revealWorld(generation)
    return true
end

local function createPointCamera(position, lookAt, fov)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    if not cam or cam == 0 or not DoesCamExist(cam) then return nil end
    SetCamCoord(cam, position.x, position.y, position.z)
    PointCamAtCoord(cam, lookAt.x, lookAt.y, lookAt.z)
    SetCamFov(cam, fov or 45.0)
    return cam
end

local function destroyCameraKey(key)
    local cam = state.cameras[key]
    if cam and DoesCamExist(cam) then DestroyCam(cam, false) end
    state.cameras[key] = nil
end

SceneRuntime.PREVIEW_SUPERSEDED = 'superseded'
local PREVIEW_SUPERSEDED = SceneRuntime.PREVIEW_SUPERSEDED

local CAMERA_WAIT_STEP_MS = 50

local function waitCameraTransition(durationMs, generation)
    local deadline = GetGameTimer() + math.max(0, tonumber(durationMs) or 0)
    while generation == state.sceneGeneration do
        local remaining = deadline - GetGameTimer()
        if remaining <= 0 then break end
        Wait(math.min(CAMERA_WAIT_STEP_MS, remaining))
    end
    return generation == state.sceneGeneration
end

local function startWorldStream(coords)
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    anchorPlayerAt(coords)
    return {
        started = requestLoadScene(coords),
        deadline = GetGameTimer() + Config.sceneLimits.worldStreamTimeoutMs,
        coords = coords,
    }
end

local function finishWorldStream(ticket, generation)
    local ped = PlayerPedId()

    while generation == state.sceneGeneration and GetGameTimer() < ticket.deadline do
        if HasCollisionLoadedAroundEntity(ped) or (ticket.started and IsNewLoadSceneLoaded()) then break end
        RequestCollisionAtCoord(ticket.coords.x, ticket.coords.y, ticket.coords.z)
        Wait(0)
    end

    if generation ~= state.sceneGeneration then return false end
    if IsNewLoadSceneActive() then NewLoadSceneStop() end

    return true
end

---The plain, non-cinematic spawn shot: stream the destination and point a
---camera at it. Used for the first preview of a session, and whenever the
---cinematic flight cannot continue from the camera it has.
---
---The player is always shown the place they picked, never a fallback spawn:
---the ped is parked at the destination (see streamWorld), and late-popping
---props are better than showing a location they did not choose.
---@param location table
---@param generation integer
local function staticSpawnPreview(location, generation)
    local coords, preview = location.coords, location.preview or {}

    announcePreviewStage(generation, 'streaming')
    if not streamWorld(coords, generation) then return false, false, PREVIEW_SUPERSEDED end

    local lookAt = preview.lookAt or vector3(coords.x, coords.y, coords.z + 0.5)
    local cameraCoords = resolveCameraPosition(
        preview.camera or vector3(coords.x + 8.0, coords.y - 8.0, coords.z + 6.0),
        lookAt,
        PlayerPedId()
    )
    if generation ~= state.sceneGeneration then return false, false, PREVIEW_SUPERSEDED end
    applyEnvironment(preview.environment)

    local cam = createPointCamera(cameraCoords, lookAt, preview.fov or 45.0)
    if not cam then
        failLoad(generation, 'spawn camera could not be created')
        return false, false, 'the spawn camera could not be created'
    end
    state.cameras.spawn, state.activeCam = cam, cam
    state.spawnLookAt, state.spawnPosition = lookAt, cameraCoords
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 450, true, true)
    revealWorld(generation)
    announcePreviewLive(generation)
    return true, true
end

---Worst-case wall time previewSpawn can legitimately spend before it answers,
---derived from the same config values the flight and the streamer read. The
---NUI races its own timeout against the focus callback and needs this figure
---to set it: the number it used to hardcode was a fifth of the real budget,
---so every slow world stream was reported to the player as a broken preview
---while Lua was still working correctly. Several config values feed the total,
---which is exactly why nothing downstream should be restating it by hand.
---@return integer ms
function SceneRuntime.spawnPreviewBudgetMs()
    local flight = Config.spawnFlight or {}
    local worldStream = STREAM_START_WINDOW_MS + Config.sceneLimits.worldStreamTimeoutMs
    return FADE_OUT_WAIT_MS * 2
        + (tonumber(flight.liftDurationMs) or 900)
        + (tonumber(flight.maxTravelDurationMs) or 4200)
        + (tonumber(flight.descentDurationMs) or 1450)
        + worldStream
end

function SceneRuntime.previewSpawn(location)
    state.sceneGeneration = state.sceneGeneration + 1
    local generation = state.sceneGeneration
    if not location or not location.coords then
        failLoad(generation, 'spawn location has no coordinates')
        return false, false, 'that location has no coordinates'
    end

    local currentCam = state.cameras.spawn
    if not currentCam or not DoesCamExist(currentCam) or not state.spawnLookAt then
        if not fadeWorldOut(generation) then return false, false, PREVIEW_SUPERSEDED end
        cleanupScene()
        return staticSpawnPreview(location, generation)
    end

    local coords = location.coords
    local preview = location.preview or {}
    local targetLookAt = preview.lookAt or vector3(coords.x, coords.y, coords.z + 0.5)
    local targetCamera = preview.camera or vector3(coords.x + 8.0, coords.y - 8.0, coords.z + 6.0)
    local settings = Config.spawnFlight or {}
    local oldLookAt = state.spawnLookAt
    local oldPosition = GetFinalRenderedCamCoord()
    if not oldPosition or (oldPosition.x == 0.0 and oldPosition.y == 0.0 and oldPosition.z == 0.0) then
        oldPosition = state.spawnPosition or GetCamCoord(currentCam)
    end
    local handoffCam = createPointCamera(oldPosition, oldLookAt, math.max(50.0, GetCamFov(currentCam)))
    if handoffCam then
        destroyCameraKey('spawnHandoff')
        state.cameras.spawnHandoff = handoffCam
        SetCamActive(handoffCam, true)
        currentCam = handoffCam
    end
    local dx, dy, dz = targetLookAt.x - oldLookAt.x, targetLookAt.y - oldLookAt.y, targetLookAt.z - oldLookAt.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local altitude = math.min(tonumber(settings.maxAltitude) or 420.0,
        math.max(tonumber(settings.minAltitude) or 180.0, distance * 0.10))
    local liftPosition = vector3(
        oldPosition.x,
        oldPosition.y,
        oldLookAt.z + math.max(tonumber(settings.liftHeight) or 130.0, altitude)
    )

    local approachX, approachY = targetCamera.x - targetLookAt.x, targetCamera.y - targetLookAt.y
    local approachLength = math.sqrt(approachX * approachX + approachY * approachY)
    if approachLength < 0.01 then approachX, approachY, approachLength = 1.0, -1.0, math.sqrt(2.0) end
    local approachDistance = math.min(120.0, math.max(35.0, distance * 0.035))
    local travelPosition = vector3(
        targetLookAt.x + approachX / approachLength * approachDistance,
        targetLookAt.y + approachY / approachLength * approachDistance,
        targetLookAt.z + altitude
    )
    local travelDuration = math.floor(distance / math.max(1.0, tonumber(settings.unitsPerSecond) or 650.0) * 1000.0)
    travelDuration = math.min(tonumber(settings.maxTravelDurationMs) or 4200,
        math.max(tonumber(settings.minTravelDurationMs) or 1400, travelDuration))
    local ticket = startWorldStream(coords)

    local function recoverStaticPreview()
        if generation ~= state.sceneGeneration or not fadeWorldOut(generation) then return false, false, PREVIEW_SUPERSEDED end
        cleanupScene()
        return staticSpawnPreview(location, generation)
    end

    local liftCam = createPointCamera(liftPosition, oldLookAt, math.max(50.0, GetCamFov(currentCam)))
    if not liftCam then return recoverStaticPreview() end
    destroyCameraKey('spawnLift')
    state.cameras.spawnLift, state.activeCam = liftCam, liftCam
    SetCamActiveWithInterp(liftCam, currentCam, tonumber(settings.liftDurationMs) or 900, true, true)
    if not waitCameraTransition(settings.liftDurationMs or 900, generation) then return false, false, PREVIEW_SUPERSEDED end

    local travelCam = createPointCamera(travelPosition, targetLookAt, 58.0)
    if not travelCam then return recoverStaticPreview() end
    destroyCameraKey('spawnTravel')
    state.cameras.spawnTravel, state.activeCam = travelCam, travelCam
    SetCamActiveWithInterp(travelCam, liftCam, travelDuration, true, true)
    if not waitCameraTransition(travelDuration, generation) then return false, false, PREVIEW_SUPERSEDED end

    local streamed = finishWorldStream(ticket, generation)
    if generation ~= state.sceneGeneration then return false, false, PREVIEW_SUPERSEDED end

    targetCamera = resolveCameraPosition(targetCamera, targetLookAt, PlayerPedId())
    if generation ~= state.sceneGeneration then return false, false, PREVIEW_SUPERSEDED end
    applyEnvironment(preview.environment)
    local finalCam = createPointCamera(targetCamera, targetLookAt, preview.fov or 45.0)
    if not finalCam then return recoverStaticPreview() end
    destroyCameraKey('spawnNext')
    state.cameras.spawnNext, state.activeCam = finalCam, finalCam
    SetCamActiveWithInterp(finalCam, travelCam, tonumber(settings.descentDurationMs) or 1450, true, true)
    if not waitCameraTransition(settings.descentDurationMs or 1450, generation) then return false, false, PREVIEW_SUPERSEDED end

    destroyCameraKey('spawn')
    destroyCameraKey('spawnHandoff')
    destroyCameraKey('spawnLift')
    destroyCameraKey('spawnTravel')
    state.cameras.spawnNext = nil
    state.cameras.spawn, state.activeCam = finalCam, finalCam
    state.spawnLookAt, state.spawnPosition = targetLookAt, targetCamera
    announcePreviewLive(generation)
    return true, streamed
end

local CONTROL_JUMP = 22 -- Space: cuts the arrival flight short
local LANDING_WAIT_MS = 1500 -- longest the arrival waits for the ped to reach the ground

---Where the camera that is rendering right now is, and a point it is looking
---at, so a flight can start from exactly the shot the player is looking at.
---Falls back to the active scene camera when the render camera reports
---nothing (e.g. before the first frame).
---@return table|nil position, table|nil lookAt, number|nil fov
local function currentShot()
    local position = GetFinalRenderedCamCoord()
    if (not position or (position.x == 0.0 and position.y == 0.0 and position.z == 0.0))
        and state.activeCam and DoesCamExist(state.activeCam) then
        position = GetCamCoord(state.activeCam)
    end
    if not position or (position.x == 0.0 and position.y == 0.0 and position.z == 0.0) then return nil end

    local rotation = GetFinalRenderedCamRot(2)
    if not rotation then return nil end
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local reach = 30.0
    local lookAt = vector3(
        position.x + -math.sin(yaw) * math.cos(pitch) * reach,
        position.y + math.cos(yaw) * math.cos(pitch) * reach,
        position.z + math.sin(pitch) * reach
    )
    local fov = GetFinalRenderedCamFov()
    return position, lookAt, (fov and fov > 0.0) and fov or 45.0
end

---The default arrival framing for a location with no authored preview shot:
---behind and above the ped, looking at them, so the hand-off to the gameplay
---camera (which also sits behind the ped) is a short move.
---@param coords table vector4 with heading in .w
---@return table camera, table lookAt
local function defaultArrivalShot(coords)
    local heading = math.rad(coords.w or coords.h or 0.0)
    local behind = 7.0
    return vector3(
        coords.x + math.sin(heading) * behind,
        coords.y - math.cos(heading) * behind,
        coords.z + 2.6
    ), vector3(coords.x, coords.y, coords.z + 0.6)
end

---Flies the camera from the character scene to an arrival point, in real
---script cameras: lift out of the scene, cruise across, descend into the
---arrival shot. The destination streams in while the camera moves, so the wait
---that used to block every location pick is hidden inside this flight.
---
---Leaves the player's (hidden, frozen) ped parked at the destination and the
---final shot rendering. SceneRuntime.completeArrival takes it from there. On a
---false return nothing is committed and the caller should fall back to a plain
---fade-out/teleport/fade-in.
---@param location table { coords = vector4, preview = { camera, lookAt, fov, environment }|nil }
---@param opts table|nil { skippable = boolean, onStage = fun(stage: string) }
---@return boolean ok
---@return string|nil reason
function SceneRuntime.flyToArrival(location, opts)
    opts = opts or {}
    state.sceneGeneration = state.sceneGeneration + 1
    local generation = state.sceneGeneration
    if not location or not location.coords then return false, 'that location has no coordinates' end

    local function stage(name)
        if opts.onStage and generation == state.sceneGeneration then pcall(opts.onStage, name) end
    end

    local startPosition, startLookAt, startFov = currentShot()
    if not startPosition then return false, 'there is no camera to start the flight from' end

    local coords = location.coords
    local preview = location.preview or {}
    local settings = Config.spawnFlight or {}
    local defaultCamera, defaultLookAt = defaultArrivalShot(coords)
    local targetLookAt = preview.lookAt or defaultLookAt
    local targetCamera = preview.camera or defaultCamera

    -- Space shortens the camera travel; everything that has to happen (the
    -- destination streaming, the ped being placed) still does.
    local skipped = false
    local function duration(ms) return skipped and 0 or ms end
    local function wait(durationMs, ignoreSkip)
        local deadline = GetGameTimer() + math.max(0, tonumber(durationMs) or 0)
        while generation == state.sceneGeneration and (ignoreSkip or not skipped) do
            if not ignoreSkip and opts.skippable and IsDisabledControlJustPressed(0, CONTROL_JUMP) then
                skipped = true
                break
            end
            if GetGameTimer() >= deadline then break end
            Wait(0)
        end
        return generation == state.sceneGeneration
    end

    local handoff = createPointCamera(startPosition, startLookAt, startFov)
    if not handoff then return false, 'the flight camera could not be created' end
    destroyCameraKey('arrivalHandoff')
    state.cameras.arrivalHandoff, state.activeCam = handoff, handoff
    SetCamActive(handoff, true)

    local dx, dy, dz = targetLookAt.x - startLookAt.x, targetLookAt.y - startLookAt.y, targetLookAt.z - startLookAt.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local altitude = math.min(tonumber(settings.maxAltitude) or 420.0,
        math.max(tonumber(settings.minAltitude) or 180.0, distance * 0.10))
    local liftPosition = vector3(
        startPosition.x, startPosition.y,
        startPosition.z + math.max(tonumber(settings.liftHeight) or 130.0, altitude)
    )
    local approachX, approachY = targetCamera.x - targetLookAt.x, targetCamera.y - targetLookAt.y
    local approachLength = math.sqrt(approachX * approachX + approachY * approachY)
    if approachLength < 0.01 then approachX, approachY, approachLength = 1.0, -1.0, math.sqrt(2.0) end
    local approachDistance = math.min(120.0, math.max(35.0, distance * 0.035))
    local travelPosition = vector3(
        targetLookAt.x + approachX / approachLength * approachDistance,
        targetLookAt.y + approachY / approachLength * approachDistance,
        targetLookAt.z + altitude
    )
    local travelDuration = math.floor(distance / math.max(1.0, tonumber(settings.unitsPerSecond) or 650.0) * 1000.0)
    travelDuration = math.min(tonumber(settings.maxTravelDurationMs) or 4200,
        math.max(tonumber(settings.minTravelDurationMs) or 1400, travelDuration))
    local liftDuration = tonumber(settings.liftDurationMs) or 900
    local descentDuration = tonumber(settings.descentDurationMs) or 1450

    -- Lift: rise out of the scene while the scene is still what is streamed.
    stage('lift')
    local liftCam = createPointCamera(liftPosition, startLookAt, math.max(50.0, startFov))
    if not liftCam then return false, 'the flight camera could not be created' end
    destroyCameraKey('arrivalLift')
    state.cameras.arrivalLift, state.activeCam = liftCam, liftCam
    SetCamActiveWithInterp(liftCam, handoff, liftDuration, true, true)
    if not wait(liftDuration) then return false, PREVIEW_SUPERSEDED end

    -- Cruise: now the camera is high, move the streaming focus to the
    -- destination and travel there while it loads.
    stage('cruise')
    local ticket = startWorldStream(coords)
    local travelCam = createPointCamera(travelPosition, targetLookAt, 58.0)
    if not travelCam then return false, 'the flight camera could not be created' end
    destroyCameraKey('arrivalTravel')
    state.cameras.arrivalTravel, state.activeCam = travelCam, travelCam
    SetCamActiveWithInterp(travelCam, liftCam, duration(travelDuration), true, true)
    if not wait(travelDuration) then return false, PREVIEW_SUPERSEDED end

    finishWorldStream(ticket, generation)
    if generation ~= state.sceneGeneration then return false, PREVIEW_SUPERSEDED end

    -- Descent: the scene's weather and clock stop applying, so the player sees
    -- the real world they are about to stand in, then settle into the shot.
    stage('descent')
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    NetworkClearClockTimeOverride()
    ClearTimecycleModifier()
    applyEnvironment(preview.environment)
    targetCamera = resolveCameraPosition(targetCamera, targetLookAt, PlayerPedId())
    if generation ~= state.sceneGeneration then return false, PREVIEW_SUPERSEDED end
    local finalCam = createPointCamera(targetCamera, targetLookAt, preview.fov or 45.0)
    if not finalCam then return false, 'the flight camera could not be created' end
    destroyCameraKey('arrival')
    state.cameras.arrival, state.activeCam = finalCam, finalCam
    local descent = skipped and 450 or descentDuration
    SetCamActiveWithInterp(finalCam, travelCam, descent, true, true)
    if not wait(descent, true) then return false, PREVIEW_SUPERSEDED end
    return true
end

-- The asset the arrival effect needs, requested while the camera is still
-- flying so it is resident when the ped arrives. Requesting it only at the
-- moment of arrival meant waiting on the streamer, and a late or missed load
-- showed as no effect at all.
local arrivalEffectAsset = nil

---Starts loading the arrival effect's asset without blocking. Call it before
---the flight; completeArrival then finds it ready.
---@param config table|nil Config.arrival.ptfx
function SceneRuntime.preloadArrivalEffect(config)
    if type(config) ~= 'table' or config.enabled == false or type(config.asset) ~= 'string' then return end
    if arrivalEffectAsset == config.asset then return end
    local asset = config.asset
    arrivalEffectAsset = asset
    CreateThread(function()
        local called, loaded = pcall(Kora.stream.loadPtfx, asset, nil, { timeout = 5000 })
        if (not called or loaded == false) and arrivalEffectAsset == asset then arrivalEffectAsset = nil end
    end)
end

---Gives the preloaded asset back, for when the arrival never got to use it.
function SceneRuntime.releaseArrivalEffect()
    if arrivalEffectAsset then RemoveNamedPtfxAsset(arrivalEffectAsset) end
    arrivalEffectAsset = nil
end

-- Effects in flight, per asset, so an asset is only handed back once the last
-- effect that used it has had time to finish (two arrivals can overlap).
local effectUsers = {}

---Starts one non-looped effect and schedules the asset's release. The asset
---must already be loaded.
local function startEffect(asset, effect, scale, x, y, z, releaseAfterMs)
    UseParticleFxAssetNextCall(asset)
    StartParticleFxNonLoopedAtCoord(effect, x, y, z, 0.0, 0.0, 0.0, scale, false, false, false)
    effectUsers[asset] = (effectUsers[asset] or 0) + 1
    SetTimeout(releaseAfterMs, function()
        effectUsers[asset] = math.max(0, (effectUsers[asset] or 1) - 1)
        if effectUsers[asset] == 0 then
            RemoveNamedPtfxAsset(asset)
            if arrivalEffectAsset == asset then arrivalEffectAsset = nil end
        end
    end)
end

local function ensureEffectAsset(asset, timeoutMs)
    if HasNamedPtfxAssetLoaded(asset) then return true end
    local called, loaded = pcall(Kora.stream.loadPtfx, asset, nil, { timeout = timeoutMs })
    return called and loaded ~= false
end

---Plays the arrival particle effect at a point (the ped's feet). Failing to
---load the effect never blocks the arrival.
---
---The arriving player sees it locally and, with `config.synced`, asks the
---server to show it to players nearby (qbmultichar:server:arrivalEffect). The
---request carries only the position: the server decides what is played.
---@param config table Config.arrival.ptfx
---@param coords table
local function playArrivalEffect(config, coords)
    if type(config) ~= 'table' or config.enabled == false then return end
    if type(config.asset) ~= 'string' or type(config.effect) ~= 'string' then return end
    if not ensureEffectAsset(config.asset, 1500) then return end
    local x, y, z = coords.x, coords.y, coords.z + (tonumber(config.zOffset) or 0.0)
    startEffect(config.asset, config.effect, tonumber(config.scale) or 1.0, x, y, z,
        tonumber(config.releaseAfterMs) or 4000)
    if config.synced ~= false then TriggerServerEvent('qbmultichar:server:arrivalEffect', x, y, z) end
end

---Plays another player's arrival effect on this client. Everything is checked
---here as well as on the server: this is a network event, so it is input.
---@param asset any
---@param effect any
---@param scale any
---@param x any
---@param y any
---@param z any
---@return boolean played
function SceneRuntime.playSyncedArrivalEffect(asset, effect, scale, x, y, z)
    if type(asset) ~= 'string' or type(effect) ~= 'string' then return false end
    if #asset == 0 or #asset > 64 or #effect == 0 or #effect > 64 then return false end
    local position = { x, y, z }
    for slot = 1, 3 do
        local value = position[slot]
        if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return false end
    end
    scale = type(scale) == 'number' and scale == scale and math.min(10.0, math.max(0.1, scale)) or 1.0
    if not ensureEffectAsset(asset, 1500) then return false end
    startEffect(asset, effect, scale, x, y, z, 4000)
    return true
end

---The ground height under an arrival point, or nil when none is found close
---enough to trust. Probed from just above the point so a floor above the
---point is not mistaken for it.
---@param coords table
---@return number|nil
local function groundUnder(coords)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    for _, lift in ipairs({ 1.0, 3.0 }) do
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + lift, false)
        if found and math.abs(groundZ - coords.z) <= 4.0 then return groundZ end
    end
    return nil
end

---The arrival itself, run after flyToArrival has settled on the final shot.
---Puts the ped on the arrival point (invisible), lets the caller run login
---side effects while they are hidden, then plays the effect, fades the ped in
---and blends the camera back to the gameplay camera. HUD and controls stay off
---until the end, exactly as during character select.
---@param coords table vector4 arrival point
---@param opts table|nil { onPlaced = fun(), settleMs, pedFadeMs, handbackMs, ptfx }
function SceneRuntime.completeArrival(coords, opts)
    opts = opts or {}
    local settle = math.max(0, tonumber(opts.settleMs) or 0)
    local pedFade = math.max(0, tonumber(opts.pedFadeMs) or 0)
    local handback = math.max(0, tonumber(opts.handbackMs) or 0)
    local heading = coords.w or coords.h or 0.0

    -- The hidden-ped watcher would re-hide a swapped ped behind our back.
    state.hiddenPed = nil
    Kora.cache.offChange('ped')

    -- A ped's root sits about a metre above the ground it stands on. Where the
    -- ground can be found the ped is placed at that standing height, so it has
    -- nothing to fall and the effect can start at once; otherwise it is placed
    -- at the coordinate and drops while invisible. It is never frozen mid-air.
    local ground = groundUnder(coords)
    local placeZ = (ground and ground + 1.0 or coords.z) + (tonumber(opts.zOffset) or 0.0)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, placeZ, false, false, false, true)
    SetEntityHeading(ped, heading)
    NetworkResurrectLocalPlayer(coords.x, coords.y, placeZ, heading, 0, false)
    ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, placeZ, false, false, false, true)
    SetEntityHeading(ped, heading)
    SetEntityAlpha(ped, 0, false)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    if opts.onPlaced then pcall(opts.onPlaced) end
    if settle > 0 then Wait(settle) end

    -- Whatever the login changed (saved outfit, starter outfit) is on by now.
    -- Applying an outfit can replace the player's ped entirely, so the ped is
    -- looked up again here and on every frame below rather than trusting the
    -- handle from before the login.
    ped = PlayerPedId()
    local landing = GetGameTimer() + LANDING_WAIT_MS
    while IsEntityInAir(ped) and GetGameTimer() < landing do
        Wait(0)
        ped = PlayerPedId()
    end
    local feet = GetEntityCoords(ped)
    local feetZ = ground or (feet.z - 1.0)
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 0, false)
    SetGameplayCamRelativeHeading(0.0)
    SetGameplayCamRelativePitch(0.0, 1.0)
    RenderScriptCams(false, true, handback, true, true)
    playArrivalEffect(opts.ptfx, { x = feet.x, y = feet.y, z = feetZ })

    local started = GetGameTimer()
    local total = math.max(handback, pedFade)
    while GetGameTimer() - started < total do
        local elapsed = GetGameTimer() - started
        local current = PlayerPedId()
        if current ~= ped then
            ped = current
            SetEntityVisible(ped, true, false)
        end
        if pedFade > 0 then
            SetEntityAlpha(ped, math.min(255, math.floor(255 * elapsed / pedFade)), false)
        else
            ResetEntityAlpha(ped)
        end
        Wait(0)
    end
    ResetEntityAlpha(PlayerPedId())

    SceneRuntime.endMode({ keepPlacement = true })
end

function SceneRuntime.cleanupScene()
    state.sceneGeneration = state.sceneGeneration + 1
    cleanupScene()
end

---@param options table|nil { keepPlacement = boolean } keepPlacement leaves the
---ped where the arrival put it instead of returning it to where it stood
---before character select.
function SceneRuntime.endMode(options)
    state.sceneGeneration = state.sceneGeneration + 1
    cleanupScene()
    state.modeActive = false
    state.hiddenPed = nil
    Kora.cache.offChange('ped')
    local ped, previous = PlayerPedId(), state.playerState or {}

    ClearFocus()

    if previous.coords and not (options and options.keepPlacement) then
        SetEntityCoordsNoOffset(ped, previous.coords.x, previous.coords.y, previous.coords.z, false, false, false)
        SetEntityHeading(ped, previous.heading or 0.0)
    end

    -- An arrival is a spawn: the ped is shown and free to move whatever state
    -- it was in when character select began (it connects hidden and frozen).
    -- Anything else returns the ped to the state it had before select.
    local arrived = options and options.keepPlacement
    SetEntityVisible(ped, arrived or previous.visible ~= false, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, previous.invincible == true)
    FreezeEntityPosition(ped, not arrived and previous.frozen == true)
    DoScreenFadeIn(350)
    state.playerState = nil
end

function SceneRuntime.currentScene()
    return state.scene
end

function SceneRuntime.playCue(cue)
    if type(cue) == 'table' then playCue(cue) end
end

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SceneRuntime.endMode()
    for asset in pairs(pendingAssets) do
        if asset.requested and not asset.released then
            asset.release(asset.name)
            asset.owned, asset.released = false, true
        end
    end
    pendingAssets = {}
end)
