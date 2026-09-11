-- In-game scene studio. It edits the exact SceneSchema payload consumed by the
-- runtime and exports deterministic Lua; it never writes files or a database.

local creator = {
    active = false,
    cursor = true,
    draft = nil,
    catalog = {},
    cam = nil,
    camCoords = nil,
    camRot = nil,
}
local cameraWorkerGeneration = 0

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function destroyEditorCamera()
    if creator.cam and DoesCamExist(creator.cam) then DestroyCam(creator.cam, false) end
    creator.cam = nil
end

local function forwardVector(rotation)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local cosPitch = math.abs(math.cos(pitch))
    return vector3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

local function startCameraWorker()
    cameraWorkerGeneration = cameraWorkerGeneration + 1
    local generation = cameraWorkerGeneration

    CreateThread(function()
        while creator.active and generation == cameraWorkerGeneration do
            if creator.cursor or not creator.cam then
                Wait(100)
            else
                local dt = GetFrameTime()
                local lookX = GetDisabledControlNormal(0, 1)
                local lookY = GetDisabledControlNormal(0, 2)
                creator.camRot = vector3(
                    math.max(-89.0, math.min(89.0, creator.camRot.x - lookY * Config.creator.lookSensitivity)),
                    0.0,
                    creator.camRot.z - lookX * Config.creator.lookSensitivity
                )
                local forward = forwardVector(creator.camRot)
                local right = vector3(math.cos(math.rad(creator.camRot.z)), math.sin(math.rad(creator.camRot.z)), 0.0)
                local speed = Config.creator.moveSpeed * (IsDisabledControlPressed(0, 21) and Config.creator.fastMultiplier or 1.0) * dt
                if IsDisabledControlPressed(0, 32) then creator.camCoords = creator.camCoords + forward * speed end
                if IsDisabledControlPressed(0, 33) then creator.camCoords = creator.camCoords - forward * speed end
                if IsDisabledControlPressed(0, 34) then creator.camCoords = creator.camCoords - right * speed end
                if IsDisabledControlPressed(0, 35) then creator.camCoords = creator.camCoords + right * speed end
                if IsDisabledControlPressed(0, 44) then creator.camCoords = creator.camCoords + vector3(0.0, 0.0, speed) end
                if IsDisabledControlPressed(0, 38) then creator.camCoords = creator.camCoords - vector3(0.0, 0.0, speed) end
                SetCamCoord(creator.cam, creator.camCoords.x, creator.camCoords.y, creator.camCoords.z)
                SetCamRot(creator.cam, creator.camRot.x, 0.0, creator.camRot.z, 2)
                Wait(0)
            end
        end
    end)
end

local function startEditorCamera()
    SceneRuntime.cleanupScene()
    destroyEditorCamera()
    local anchor = creator.draft.anchor
    SetFocusPosAndVel(anchor.x, anchor.y, anchor.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(anchor.x, anchor.y, anchor.z)
    creator.camCoords = creator.camCoords or vector3(anchor.x + 6.0, anchor.y - 8.0, anchor.z + 3.0)
    creator.camRot = creator.camRot or vector3(-12.0, 0.0, anchor.w or 0.0)
    creator.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(creator.cam, creator.camCoords.x, creator.camCoords.y, creator.camCoords.z)
    SetCamRot(creator.cam, creator.camRot.x, creator.camRot.y, creator.camRot.z, 2)
    SetCamFov(creator.cam, 45.0)
    RenderScriptCams(true, true, 250, true, true)
end

local function setCursor(enabled)
    if not creator.active then return end
    creator.cursor = enabled
    SetNuiFocus(enabled, enabled)
    if not enabled then startEditorCamera() end
    send('multichar:creator:cursor', { cursor = enabled })
end

local function placementPoint()
    if creator.cam then
        local ok, hit, coords = pcall(function() return QB.raycast.fromCam(creator.cam, 75.0) end)
        if ok and hit and coords then return { x = coords.x, y = coords.y, z = coords.z, w = creator.camRot.z } end
        local forward = forwardVector(creator.camRot)
        return {
            x = creator.camCoords.x + forward.x * Config.creator.placementDistance,
            y = creator.camCoords.y + forward.y * Config.creator.placementDistance,
            z = creator.camCoords.z + forward.z * Config.creator.placementDistance,
            w = creator.camRot.z,
        }
    end
    local coords = GetEntityCoords(PlayerPedId())
    return { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(PlayerPedId()) }
end

local function updateUi(errorMessage)
    send('multichar:creator:state', {
        draft = creator.draft,
        scenes = creator.catalog,
        cursor = creator.cursor,
        error = errorMessage,
    })
end

local function validateDraft()
    local normalized, err = SceneSchema.validate(creator.draft.id, creator.draft, Config.sceneLimits)
    if not normalized then return nil, err end
    for _, entity in ipairs(normalized.entities) do
        local hash = type(entity.model) == 'number' and entity.model or joaat(entity.model)
        if not IsModelInCdimage(hash) or not IsModelValid(hash) then
            return nil, ('entity %s uses an invalid base-game model'):format(entity.id)
        end
    end
    return normalized
end

local function refreshPreview()
    destroyEditorCamera()
    local normalized, err = validateDraft()
    if not normalized then updateUi(err); return false end
    creator.draft = normalized
    local ok, runtimeErr = SceneRuntime.loadCharacter(normalized, 'mp_m_freemode_01', {})
    if not ok then updateUi(runtimeErr); return false end
    if not creator.cursor then startEditorCamera() end
    updateUi()
    return true
end

local function exportDraft(registerCall)
    local normalized, err = validateDraft()
    if not normalized then updateUi(err); return end
    local definition = SceneSchema.clone(normalized)
    definition.id = nil
    local body = SceneSchema.serializeLua(definition)
    local text
    if registerCall then
        text = ("exports.qbmultichar:RegisterScene(%q, %s)"):format(normalized.id, body)
    else
        text = ("Config.scenes[%q] = %s"):format(normalized.id, body)
    end
    QB.nui.copyToClipboard(text)
    send('multichar:creator:exported', { registerCall = registerCall })
end

local function closeCreator()
    if not creator.active then return end
    creator.active = false
    cameraWorkerGeneration = cameraWorkerGeneration + 1
    destroyEditorCamera()
    SceneRuntime.endMode()
    QB.callback.trigger('qbmultichar:server:leaveMode')
    SetNuiFocus(false, false)
    send('multichar:creator:close')
    creator.draft, creator.catalog = nil, {}
end

local function newDraft()
    local coords = GetEntityCoords(PlayerPedId())
    local heading = GetEntityHeading(PlayerPedId())
    return {
        id = 'new_scene', label = 'New Scene', priority = 0, selectors = {},
        anchor = { x = coords.x, y = coords.y, z = coords.z, w = heading },
        environment = { hour = 18, minute = 0, weather = 'CLEAR' },
        character = { offset = { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }, scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        entities = {},
        cameras = {
            {
                id = 'close', offset = { x = 0.65, y = 2.65, z = 1.68 },
                lookAt = { x = 0.0, y = 0.0, z = 1.34 }, fov = 30.0,
                dof = { near = 0.8, far = 3.2, strength = 0.65 },
            },
            {
                id = 'focal', offset = { x = -7.0, y = 6.8, z = 3.35 },
                lookAt = { x = 0.0, y = 1.5, z = 0.9 }, fov = 43.0,
                transitionMs = 2100,
            },
            {
                id = 'establishing', offset = { x = -11.34, y = 11.02, z = 5.7 },
                lookAt = { x = 0.0, y = 1.5, z = 0.9 }, fov = 52.0,
                transitionMs = 2400,
            },
        },
        timeline = { durationMs = 18000, loop = true, cues = {
            { at = 0, type = 'camera', camera = 'close' },
            { at = 1700, type = 'camera', camera = 'focal', transitionMs = 2100 },
            { at = 5200, type = 'camera', camera = 'establishing', transitionMs = 2400 },
            { at = 9400, type = 'camera', camera = 'focal', transitionMs = 2200 },
            { at = 14800, type = 'camera', camera = 'close', transitionMs = 1900 },
        } },
    }
end

local function moveItem(list, index, delta)
    index, delta = tonumber(index), tonumber(delta)
    if not index or not delta then return false end
    local destination = math.max(1, math.min(#list, index + delta))
    if destination == index or not list[index] then return false end
    local value = table.remove(list, index)
    table.insert(list, destination, value)
    return true
end

RegisterNetEvent('qbmultichar:client:openCreator', function(catalog)
    if creator.active then return end
    creator.active, creator.catalog, creator.draft = true, catalog or {}, newDraft()
    creator.cursor, creator.camCoords, creator.camRot = true, nil, nil
    SceneRuntime.beginMode()
    startCameraWorker()
    SetNuiFocus(true, true)
    send('multichar:creator:show', { draft = creator.draft, scenes = creator.catalog, cursor = true })
end)

RegisterCommand('qbmultichar_creator_toggle', function()
    if creator.active then setCursor(not creator.cursor) end
end, false)
RegisterKeyMapping('qbmultichar_creator_toggle', 'Scene Studio: Toggle Cursor / Freecam', 'keyboard', 'TAB')

RegisterNUICallback('multichar:creator:action', function(data, cb)
    if not creator.active or type(data) ~= 'table' then cb({ ok = false }); return end
    local action, payload = data.action, type(data.payload) == 'table' and data.payload or {}
    if action == 'close' then closeCreator()
    elseif action == 'toggleMode' then setCursor(not creator.cursor)
    elseif action == 'new' then
        destroyEditorCamera()
        creator.draft = newDraft(); creator.camCoords, creator.camRot = nil, nil; updateUi()
    elseif action == 'duplicate' then
        local duplicate = SceneSchema.clone(creator.draft)
        local base, suffix = (duplicate.id or 'scene') .. '_copy', 1
        duplicate.id = base
        while creator.catalog[duplicate.id] do
            suffix = suffix + 1
            duplicate.id = ('%s_%d'):format(base, suffix)
        end
        duplicate.label = (duplicate.label or 'Scene') .. ' Copy'
        creator.draft = duplicate
        updateUi()
    elseif action == 'load' and creator.catalog[payload.id] then
        destroyEditorCamera()
        creator.draft = SceneSchema.clone(creator.catalog[payload.id]); creator.draft.id = payload.id
        creator.camCoords, creator.camRot = nil, nil
        updateUi()
    elseif action == 'metadata' then
        creator.draft.id = payload.id or creator.draft.id
        creator.draft.label = payload.label or creator.draft.label
        creator.draft.priority = tonumber(payload.priority) or creator.draft.priority
        if type(payload.selectors) == 'table' then creator.draft.selectors = payload.selectors end
        updateUi()
    elseif action == 'environment' then
        creator.draft.environment = payload; updateUi()
    elseif action == 'setAnchor' then
        creator.draft.anchor = placementPoint()
        destroyEditorCamera()
        creator.camCoords, creator.camRot = nil, nil
        updateUi()
    elseif action == 'placeCharacter' then
        creator.draft.character.offset = SceneSchema.worldToLocal(creator.draft.anchor, placementPoint()); updateUi()
    elseif action == 'addEntity' then
        local world = placementPoint()
        creator.draft.entities[#creator.draft.entities + 1] = {
            id = payload.id or ('entity_%d'):format(#creator.draft.entities + 1),
            type = payload.type or 'prop', model = payload.model or 'prop_tool_box_04',
            offset = SceneSchema.worldToLocal(creator.draft.anchor, world),
        }
        refreshPreview()
    elseif action == 'updateEntity' then
        for _, entity in ipairs(creator.draft.entities) do if entity.id == payload.originalId then
            for key, value in pairs(payload.values or {}) do entity[key] = value end
        end end
        refreshPreview()
    elseif action == 'replaceEntity' then
        for index, entity in ipairs(creator.draft.entities) do
            if entity.id == payload.originalId and type(payload.value) == 'table' then creator.draft.entities[index] = payload.value; break end
        end
        updateUi()
    elseif action == 'reorderEntity' then
        moveItem(creator.draft.entities, payload.index, payload.delta); updateUi()
    elseif action == 'removeEntity' then
        for index, entity in ipairs(creator.draft.entities) do if entity.id == payload.id then table.remove(creator.draft.entities, index); break end end
        refreshPreview()
    elseif action == 'captureCamera' then
        if not creator.cam then startEditorCamera() end
        local lookWorld = placementPoint()
        creator.draft.cameras[#creator.draft.cameras + 1] = {
            id = payload.id or ('camera_%d'):format(#creator.draft.cameras + 1),
            offset = SceneSchema.worldToLocal(creator.draft.anchor, { x = creator.camCoords.x, y = creator.camCoords.y, z = creator.camCoords.z }),
            lookAt = SceneSchema.worldToLocal(creator.draft.anchor, lookWorld),
            fov = tonumber(payload.fov) or 45.0, transitionMs = tonumber(payload.transitionMs) or 900,
        }
        updateUi()
    elseif action == 'removeCamera' then
        for index, camera in ipairs(creator.draft.cameras) do if camera.id == payload.id and #creator.draft.cameras > 1 then table.remove(creator.draft.cameras, index); break end end
        updateUi()
    elseif action == 'replaceCamera' then
        local index = tonumber(payload.index)
        if index and creator.draft.cameras[index] and type(payload.value) == 'table' then creator.draft.cameras[index] = payload.value end
        updateUi()
    elseif action == 'reorderCamera' then
        moveItem(creator.draft.cameras, payload.index, payload.delta); updateUi()
    elseif action == 'addCue' then
        creator.draft.timeline.cues[#creator.draft.timeline.cues + 1] = payload; updateUi()
    elseif action == 'replaceCue' then
        local index = tonumber(payload.index)
        if index and creator.draft.timeline.cues[index] and type(payload.value) == 'table' then creator.draft.timeline.cues[index] = payload.value end
        updateUi()
    elseif action == 'reorderCue' then
        moveItem(creator.draft.timeline.cues, payload.index, payload.delta); updateUi()
    elseif action == 'removeCue' then
        local index = tonumber(payload.index)
        if index and index >= 1 and index <= #creator.draft.timeline.cues then table.remove(creator.draft.timeline.cues, index) end
        updateUi()
    elseif action == 'timeline' then
        creator.draft.timeline.durationMs = tonumber(payload.durationMs) or creator.draft.timeline.durationMs
        creator.draft.timeline.loop = payload.loop == true
        updateUi()
    elseif action == 'preview' then refreshPreview()
    elseif action == 'validate' then
        local normalized, err = validateDraft()
        if normalized then
            creator.draft = normalized
            updateUi()
            send('multichar:creator:validated', { message = 'Scene is valid and ready to export.' })
        else
            updateUi(err)
        end
    elseif action == 'scrub' then
        local at = tonumber(payload.at) or 0
        for _, cue in ipairs(creator.draft.timeline.cues or {}) do if (cue.at or 0) <= at then SceneRuntime.playCue(cue) end end
    elseif action == 'exportConfig' then exportDraft(false)
    elseif action == 'exportRegister' then exportDraft(true)
    end
    cb({ ok = true })
end)

RegisterNetEvent('qbmultichar:client:sceneUpsert', function(id, definition)
    if creator.active then creator.catalog[id] = SceneSchema.clone(definition); updateUi() end
end)

RegisterNetEvent('qbmultichar:client:sceneRemove', function(id)
    if creator.active then creator.catalog[id] = nil; updateUi() end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() and creator.active then closeCreator() end
end)
