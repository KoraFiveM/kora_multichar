-- Cinematic client runtime. Every staged entity is local-only and disposed by
-- cleanupScene; the real player remains hidden in the server-owned private
-- bucket until the final spawn handoff.

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
    local loaded = QB.stream.loadModel(hash, nil, {
        timeout = Config.sceneLimits.streamTimeoutMs,
    })
    return loaded or nil
end

-- Pending loads keep their captured scene map until the bounded library call
-- completes; cancelling the shared-name loader could release a newer scene's use.
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
    return loadSceneAsset('animAssets', dict, QB.stream.loadAnimDict, HasAnimDictLoaded, RemoveAnimDict)
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

-- --- world streaming -------------------------------------------------------
--
-- The streamer loads the map around the LOCAL PLAYER PED, and only weakly
-- around a bare focus position. This used to call SetFocusPosAndVel and then
-- wait on a load scene while the ped stayed wherever it happened to be --
-- often the far side of the map -- which is why previews were slow, frequently
-- gave up, and showed a black world when they did not: nothing had actually
-- streamed at the camera.
--
-- The ped is already frozen, invisible and collision-free for the whole
-- cinematic mode (see hidePlayerPed), so moving it to the preview point costs
-- nothing visually and turns a weak hint into the streamer's primary anchor.
-- beginMode records where it started and endMode puts it back, so a player who
-- disconnects mid-selection does not persist a preview coordinate as their
-- position -- a real spawn overwrites it anyway.
--
-- The load scene is kept, but only as an accelerant. It is a HINT, not a gate:
-- on a cold client it regularly never reports itself loaded, and gating the
-- preview on it is what produced the blackout-then-error.
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

    -- NoOffset: the ped is frozen, and the offset form resolves against
    -- physics that are not running for it.
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    -- Re-asserted rather than assumed: a respawn during a long preview replaces
    -- the ped handle, and a visible, colliding player standing in the shot is
    -- exactly what the cinematic mode exists to prevent.
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

    -- Best effort, and deliberately short: if the engine will not take a load
    -- scene we carry on regardless, because the ped anchor above is doing the
    -- real work.
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
        -- Either signal is good enough. Collision around the ped is the one
        -- that actually correlates with "there is a world at the camera".
        if HasCollisionLoadedAroundEntity(ped) or (started and IsNewLoadSceneLoaded()) then
            loaded = true
            break
        end
        -- Collision requests are not sticky; re-issue while waiting.
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end

    if generation ~= state.sceneGeneration then return false, false end
    if IsNewLoadSceneActive() then NewLoadSceneStop() end

    -- A timeout still shows the destination. The ped is parked there and the
    -- streamer is working; the last of the map pops in behind the camera, which
    -- is strictly better than diverting a player to a fallback city spawn they
    -- did not choose.
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
    -- A superseded preview must stay silent: the player has already moved on,
    -- and its camera is not the one on screen.
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

-- Keep authored composition, but never accept a camera position that has map
-- geometry between it and the subject. A small capsule trace is used instead
-- of a zero-width ray so the camera does not end up grazing a wall, column, or
-- foliage edge. If the authored angle is blocked we fan around the subject at
-- the same distance before falling back to a point just in front of the first
-- obstruction.
local CAMERA_TRACE_FLAGS = 273 -- world geometry, objects, and vegetation
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

    -- A trace can time out while collision is still settling. Preserve the
    -- authored shot in that rare case rather than snapping to arbitrary world
    -- coordinates; the surrounding stream operation remains bounded.
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
    if not loadSceneAsset('ptfxAssets', cue.asset, QB.stream.loadPtfx,
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
    -- 'focus' (the default, also when unset) keeps the camera on the previewed
    -- ped: camera cues are dropped, every other cue still plays.
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
        invincible = GetPlayerInvincible(PlayerId()),
        frozen = IsEntityPositionFrozen(ped),
        -- Where the ped stood before the previews started moving it around the
        -- map to anchor the streamer (see anchorPlayerAt). Restored on endMode
        -- so a player who disconnects mid-selection does not persist whichever
        -- spawn they were last looking at as their saved position. A real spawn
        -- overwrites this immediately, so it only matters on the abandon path.
        coords = GetEntityCoords(ped),
        heading = GetEntityHeading(ped),
    }
    hidePlayerPed(ped)
    state.hiddenPed = ped
    DoScreenFadeOut(0)

    CreateThread(function()
        while state.modeActive do
            -- The game's own first spawn can still be in flight when selection
            -- opens on a cold client, and finishing it CREATES A NEW PED. The
            -- new handle is visible, unfrozen and collidable, so the hide above
            -- silently stops applying and a real player drops into the middle
            -- of the shot -- on the first load only, which is exactly why this
            -- came in as "it works on the second load, not the first".
            -- Re-assert on every handle change: one comparison per frame.
            local ped = PlayerPedId()
            if ped ~= state.hiddenPed then
                hidePlayerPed(ped)
                state.hiddenPed = ped
            end
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
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
    -- Deliberately ignores the `accepted` result. A character scene sits on an
    -- authored anchor that is known to exist, so there is nothing to fall back
    -- to and no reason to refuse the preview: the focus is set, the streamer is
    -- working, and the scene fills in behind the camera. Only a newer preview
    -- superseding this one stops here.
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

-- previewSpawn's third return separates the two ways a preview can end with no
-- camera arriving. A CANCELLED preview is not a failure: some other preview --
-- or a mode teardown -- bumped state.sceneGeneration, which retires every
-- thread fenced on the old one. That is simply what picking a different
-- location looks like from in here, so the NUI must stay silent about it;
-- every other reason is a real failure worth telling the player about.
SceneRuntime.PREVIEW_SUPERSEDED = 'superseded'
local PREVIEW_SUPERSEDED = SceneRuntime.PREVIEW_SUPERSEDED

local function waitCameraTransition(durationMs, generation)
    local deadline = GetGameTimer() + math.max(0, tonumber(durationMs) or 0)
    while generation == state.sceneGeneration and GetGameTimer() < deadline do Wait(0) end
    return generation == state.sceneGeneration
end

local function startWorldStream(coords)
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    -- Same anchor as streamWorld: the ped is the streamer's primary reference,
    -- and this variant exists only so the flight can start while the
    -- destination loads underneath it.
    anchorPlayerAt(coords)
    return {
        started = requestLoadScene(coords),
        deadline = GetGameTimer() + Config.sceneLimits.worldStreamTimeoutMs,
        coords = coords,
    }
end

local function finishWorldStream(ticket, generation)
    -- The aerial flight has been covering this since lift-off, so whatever is
    -- left of the wait happens here while the camera is still cruising.
    local ped = PlayerPedId()

    while generation == state.sceneGeneration and GetGameTimer() < ticket.deadline do
        if HasCollisionLoadedAroundEntity(ped) or (ticket.started and IsNewLoadSceneLoaded()) then break end
        RequestCollisionAtCoord(ticket.coords.x, ticket.coords.y, ticket.coords.z)
        Wait(0)
    end

    if generation ~= state.sceneGeneration then return false end
    if IsNewLoadSceneActive() then NewLoadSceneStop() end

    -- Always true. The ped has been parked at the destination since lift-off,
    -- so there is a world there whether or not the engine ever said so, and
    -- diverting the player to a fallback city spawn they did not choose is a
    -- worse outcome than a few late-popping props. Kept as a return value
    -- because the caller's shape is part of the preview contract.
    return true
end

---The plain, non-cinematic spawn shot: stream the destination and point a
---camera at it. Used for the first preview of a session, and whenever the
---cinematic flight cannot continue from the camera it has.
---
---The player is always shown the place they PICKED. There used to be a
---"the streamer refused this destination" branch that diverted to a safe city
---spawn -- which is the "That area would not load, settling on a safe spot"
---panel players were seeing. It is gone: the ped is parked at the destination
---(see streamWorld), so the area does load, and the only question is whether it
---has finished by the time the camera arrives. A few props popping in late is a
---far better answer than showing someone a location they did not choose.
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
    -- One world stream, not two: the destination is no longer abandoned for a
    -- fallback the player did not choose, so nothing is ever streamed twice.
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

    -- The first spawn shot replaces the character scene and stays fully
    -- covered while both the world and camera are being prepared. Once a
    -- spawn camera exists, navigation becomes an uninterrupted aerial flight.
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
    -- A new location can be selected while lift/travel interpolation is still
    -- running. Capture the rendered camera, not the last completed preview,
    -- so the replacement route begins exactly where the player is looking.
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
        math.max(oldPosition.z + (tonumber(settings.liftHeight) or 130.0), oldLookAt.z + altitude)
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

function SceneRuntime.cleanupScene()
    state.sceneGeneration = state.sceneGeneration + 1
    cleanupScene()
end

function SceneRuntime.endMode()
    state.sceneGeneration = state.sceneGeneration + 1
    cleanupScene()
    state.modeActive = false
    state.hiddenPed = nil
    local ped, previous = PlayerPedId(), state.playerState or {}

    -- The focus follows the ped while previewing; hand it back to the engine
    -- before the ped moves, or the streamer keeps chasing a stale anchor.
    ClearFocus()

    if previous.coords then
        SetEntityCoordsNoOffset(ped, previous.coords.x, previous.coords.y, previous.coords.z, false, false, false)
        SetEntityHeading(ped, previous.heading or 0.0)
    end

    SetEntityVisible(ped, previous.visible ~= false, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, previous.invincible == true)
    FreezeEntityPosition(ped, previous.frozen == true)
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
    -- A stopped caller cannot finish its suspended load and dispose the request.
    for asset in pairs(pendingAssets) do
        if asset.requested and not asset.released then
            asset.release(asset.name)
            asset.owned, asset.released = false, true
        end
    end
    pendingAssets = {}
end)
