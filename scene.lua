-- Cinematic client runtime. Every staged entity is local-only and disposed by
-- cleanupScene; the real player remains hidden in the server-owned private
-- bucket until the final spawn handoff.

SceneRuntime = SceneRuntime or {}

local state = {
    modeActive = false,
    sceneGeneration = 0,
    timelineGeneration = 0,
    entities = {},
    definitions = {},
    cameras = {},
    cameraDefinitions = {},
    particles = {},
    sounds = {},
    previewPed = nil,
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
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + Config.sceneLimits.streamTimeoutMs
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function loadAnim(dict)
    if type(dict) ~= 'string' or dict == '' then return false end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + Config.sceneLimits.streamTimeoutMs
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
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

local function fadeWorldOut(generation)
    if not IsScreenFadedOut() then DoScreenFadeOut(120) end
    local deadline = GetGameTimer() + 350
    while generation == state.sceneGeneration and not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
    return generation == state.sceneGeneration
end

local function revealWorld(generation)
    if generation == state.sceneGeneration then DoScreenFadeIn(350) end
end

local function streamWorld(coords, generation)
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local started = NewLoadSceneStartSphere(coords.x, coords.y, coords.z, 80.0, 0)
    local deadline = GetGameTimer() + Config.sceneLimits.streamTimeoutMs
    while started and generation == state.sceneGeneration and not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do
        -- Collision requests are not sticky. Re-issue this while the load
        -- scene is active so a cold first preview keeps making progress.
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end
    local current = generation == state.sceneGeneration
    local loaded = current and started and IsNewLoadSceneLoaded()
    if current and started then NewLoadSceneStop() end
    return loaded
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
    if GetResourceState('qbclothing') == 'started' then
        local ok, applied = pcall(function() return exports.qbclothing:ApplyAppearanceToPed(ped, model, skin or {}) end)
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

local function createCamera(scene, definition)
    local position, lookAt = localWorld(scene, definition.offset), localWorld(scene, definition.lookAt)
    local characterOffset = scene.character.offset
    local characterLookAt = localWorld(scene, {
        x = characterOffset.x,
        y = characterOffset.y,
        z = characterOffset.z + 1.15,
    })
    position = resolveCameraPosition(position, lookAt, state.previewPed, characterLookAt)
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
    RequestNamedPtfxAsset(cue.asset)
    local generation = state.timelineGeneration
    local deadline = GetGameTimer() + Config.sceneLimits.streamTimeoutMs
    while not HasNamedPtfxAssetLoaded(cue.asset) and GetGameTimer() < deadline do Wait(0) end
    if generation ~= state.timelineGeneration or not HasNamedPtfxAssetLoaded(cue.asset) then return end
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
    if #cues == 0 or (timeline.durationMs or 0) <= 0 then return end
    state.timelineGeneration = state.timelineGeneration + 1
    local generation = state.timelineGeneration
    CreateThread(function()
        repeat
            local started, index = GetGameTimer(), 1
            while generation == state.timelineGeneration and GetGameTimer() - started <= timeline.durationMs do
                local elapsed = GetGameTimer() - started
                while cues[index] and (cues[index].at or 0) <= elapsed do
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

function SceneRuntime.beginMode()
    if state.modeActive then return end
    state.modeActive = true
    local ped = PlayerPedId()
    state.playerState = {
        visible = IsEntityVisible(ped),
        invincible = GetPlayerInvincible(PlayerId()),
        frozen = IsEntityPositionFrozen(ped),
    }
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityVisible(ped, false, false)
    DoScreenFadeOut(0)

    CreateThread(function()
        while state.modeActive do
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
    if not streamWorld(scene.anchor, generation) then
        return failLoad(generation, generation == state.sceneGeneration and 'scene area could not be streamed' or 'stale preview')
    end

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
        local camera = createCamera(scene, definition)
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

local function waitCameraTransition(durationMs, generation)
    local deadline = GetGameTimer() + math.max(0, tonumber(durationMs) or 0)
    while generation == state.sceneGeneration and GetGameTimer() < deadline do Wait(0) end
    return generation == state.sceneGeneration
end

local function startWorldStream(coords)
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    return {
        started = NewLoadSceneStartSphere(coords.x, coords.y, coords.z, 80.0, 0),
        deadline = GetGameTimer() + Config.sceneLimits.streamTimeoutMs,
        coords = coords,
    }
end

local function finishWorldStream(ticket, generation)
    while ticket.started and generation == state.sceneGeneration and not IsNewLoadSceneLoaded()
        and GetGameTimer() < ticket.deadline do
        RequestCollisionAtCoord(ticket.coords.x, ticket.coords.y, ticket.coords.z)
        Wait(0)
    end
    local current = generation == state.sceneGeneration
    local loaded = current and ticket.started and IsNewLoadSceneLoaded()
    if current and ticket.started and IsNewLoadSceneActive() then NewLoadSceneStop() end
    return loaded
end

local function staticSpawnPreview(location, generation, forceSafe)
    local coords, preview = location.coords, location.preview or {}
    local safe = (Config.spawns.legion and Config.spawns.legion.coords) or Config.defaultSpawn
    local streamed, displayCoords = false, coords

    if not forceSafe then streamed = streamWorld(coords, generation) end
    if generation ~= state.sceneGeneration then return false, false end
    if not streamed then
        displayCoords = safe
        if not streamWorld(safe, generation) then
            failLoad(generation, 'spawn area and safe fallback could not be streamed')
            return false, false
        end
    end

    local cameraCoords = streamed and (preview.camera or vector3(coords.x + 8.0, coords.y - 8.0, coords.z + 6.0))
        or vector3(displayCoords.x + 12.0, displayCoords.y - 12.0, displayCoords.z + 9.0)
    local lookAt = streamed and (preview.lookAt or vector3(coords.x, coords.y, coords.z + 0.5))
        or vector3(displayCoords.x, displayCoords.y, displayCoords.z + 0.5)
    cameraCoords = resolveCameraPosition(cameraCoords, lookAt, PlayerPedId())
    applyEnvironment(streamed and preview.environment or nil)

    local cam = createPointCamera(cameraCoords, lookAt, streamed and (preview.fov or 45.0) or 45.0)
    if not cam then
        failLoad(generation, 'spawn camera could not be created')
        return false, false
    end
    state.cameras.spawn, state.activeCam = cam, cam
    state.spawnLookAt, state.spawnPosition = lookAt, cameraCoords
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 450, true, true)
    revealWorld(generation)
    return true, streamed
end

function SceneRuntime.previewSpawn(location)
    state.sceneGeneration = state.sceneGeneration + 1
    local generation = state.sceneGeneration
    if not location or not location.coords then
        failLoad(generation, 'spawn location has no coordinates')
        return false, false
    end

    -- The first spawn shot replaces the character scene and stays fully
    -- covered while both the world and camera are being prepared. Once a
    -- spawn camera exists, navigation becomes an uninterrupted aerial flight.
    local currentCam = state.cameras.spawn
    if not currentCam or not DoesCamExist(currentCam) or not state.spawnLookAt then
        if not fadeWorldOut(generation) then return false, false end
        cleanupScene()
        return staticSpawnPreview(location, generation, false)
    end

    local coords = location.coords
    local preview = location.preview or {}
    local targetLookAt = preview.lookAt or vector3(coords.x, coords.y, coords.z + 0.5)
    local targetCamera = preview.camera or vector3(coords.x + 8.0, coords.y - 8.0, coords.z + 6.0)
    local settings = Config.spawnFlight or {}
    local oldLookAt = state.spawnLookAt
    local oldPosition = state.spawnPosition or GetCamCoord(currentCam)
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
        if generation ~= state.sceneGeneration or not fadeWorldOut(generation) then return false, false end
        cleanupScene()
        return staticSpawnPreview(location, generation, false)
    end

    local liftCam = createPointCamera(liftPosition, oldLookAt, math.max(50.0, GetCamFov(currentCam)))
    if not liftCam then return recoverStaticPreview() end
    state.cameras.spawnLift, state.activeCam = liftCam, liftCam
    SetCamActiveWithInterp(liftCam, currentCam, tonumber(settings.liftDurationMs) or 900, true, true)
    if not waitCameraTransition(settings.liftDurationMs or 900, generation) then return false, false end

    local travelCam = createPointCamera(travelPosition, targetLookAt, 58.0)
    if not travelCam then return recoverStaticPreview() end
    state.cameras.spawnTravel, state.activeCam = travelCam, travelCam
    SetCamActiveWithInterp(travelCam, liftCam, travelDuration, true, true)
    if not waitCameraTransition(travelDuration, generation) then return false, false end

    local streamed = finishWorldStream(ticket, generation)
    if generation ~= state.sceneGeneration then return false, false end
    if not streamed then
        -- Never reveal an unstreamed destination. Cover the rare failure and
        -- settle onto the known-safe city fallback instead.
        if not fadeWorldOut(generation) then return false, false end
        cleanupScene()
        return staticSpawnPreview(location, generation, true)
    end

    targetCamera = resolveCameraPosition(targetCamera, targetLookAt, PlayerPedId())
    applyEnvironment(preview.environment)
    local finalCam = createPointCamera(targetCamera, targetLookAt, preview.fov or 45.0)
    if not finalCam then return recoverStaticPreview() end
    state.cameras.spawnNext, state.activeCam = finalCam, finalCam
    SetCamActiveWithInterp(finalCam, travelCam, tonumber(settings.descentDurationMs) or 1450, true, true)
    if not waitCameraTransition(settings.descentDurationMs or 1450, generation) then return false, false end

    destroyCameraKey('spawn')
    destroyCameraKey('spawnLift')
    destroyCameraKey('spawnTravel')
    state.cameras.spawnNext = nil
    state.cameras.spawn, state.activeCam = finalCam, finalCam
    state.spawnLookAt, state.spawnPosition = targetLookAt, targetCamera
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
    local ped, previous = PlayerPedId(), state.playerState or {}
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
    if resource == GetCurrentResourceName() then SceneRuntime.endMode() end
end)
