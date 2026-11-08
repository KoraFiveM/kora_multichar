-- In-game scene studio. It edits the exact SceneSchema payload consumed by the
-- runtime and exports deterministic Lua; it never writes files or a database.

local creator = {
    active = false,
    cursor = true,
    draft = nil,
    catalog = {},
    freecam = nil,
    cam = nil,
    camCoords = nil,
    camRot = nil,
    instructions = nil,
    placing = false,
}
local creatorToggleBinding
local updateUi

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function destroyEditorCamera()
    if creator.freecam then
        creator.camCoords = creator.freecam.getCoords() or creator.camCoords
        local rotation = creator.freecam.getRotation()
        if rotation then creator.camRot = vector3(rotation.pitch, rotation.roll, rotation.yaw) end
        creator.freecam.stop()
        creator.freecam = nil
    end
    if creator.instructions then
        creator.instructions.hide()
        creator.instructions = nil
    end
    creator.cam = nil
end

local function forwardVector(rotation)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local cosPitch = math.abs(math.cos(pitch))
    return vector3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

local function startEditorCamera()
    SceneRuntime.cleanupScene()
    destroyEditorCamera()
    local anchor = creator.draft.anchor
    SetFocusPosAndVel(anchor.x, anchor.y, anchor.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(anchor.x, anchor.y, anchor.z)
    creator.camCoords = creator.camCoords or vector3(anchor.x + 6.0, anchor.y - 8.0, anchor.z + 3.0)
    creator.camRot = creator.camRot or vector3(-12.0, 0.0, anchor.w or 0.0)
    local freecam, err = Kora.freecam.start({
        coords = creator.camCoords,
        rotation = creator.camRot,
        fov = 45.0,
        moveSpeed = Config.creator.moveSpeed,
        lookSensitivity = Config.creator.lookSensitivity,
        fastMultiplier = Config.creator.fastMultiplier,
        transitionMs = 250,
        upControl = 44,
        downControl = 38,
        freezePlayer = false,
    })
    if not freecam then return false, err end
    creator.freecam, creator.cam = freecam, freecam.getCamera()
    creator.instructions = Kora.instructional.show({
        { control = 32, label = 'Move forward' },
        { control = 33, label = 'Move backward' },
        { control = 34, label = 'Move left' },
        { control = 35, label = 'Move right' },
        { control = 44, label = 'Move up' },
        { control = 38, label = 'Move down' },
        { control = 21, label = 'Move faster' },
        { keybind = creatorToggleBinding, label = 'Show cursor' },
    })
    return true
end

local function setCursor(enabled)
    if not creator.active or creator.placing then return end
    creator.cursor = enabled
    if not enabled then
        local started, err = startEditorCamera()
        if not started then
            creator.cursor = true
            updateUi(err)
            return
        end
    else
        destroyEditorCamera()
    end
    SetNuiFocus(enabled, enabled)
    send('multichar:creator:cursor', { cursor = enabled })
end

local function placementPoint()
    if creator.cam then
        creator.camCoords = creator.freecam.getCoords() or creator.camCoords
        local rotation = creator.freecam.getRotation()
        if rotation then creator.camRot = vector3(rotation.pitch, rotation.roll, rotation.yaw) end
        local ok, hit, coords = pcall(function() return Kora.raycast.fromCam(creator.cam, 75.0) end)
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

-- `selected` (an entity id) tells the panel which row to select; nil leaves the
-- player's current selection alone.
updateUi = function(errorMessage, selected)
    send('multichar:creator:state', {
        draft = creator.draft,
        scenes = creator.catalog,
        cursor = creator.cursor,
        placing = creator.placing,
        selected = selected,
        error = errorMessage,
    })
end

local ENTITY_LIMIT_KEY = { ped = 'maxPeds', vehicle = 'maxVehicles', prop = 'maxProps' }

-- ped_1, vehicle_2, prop_3 ... first free number, so nobody types an id.
local function nextEntityId(kind)
    local used = {}
    for _, entity in ipairs(creator.draft.entities) do used[entity.id] = true end
    local n = 1
    while used[('%s_%d'):format(kind, n)] do n = n + 1 end
    return ('%s_%d'):format(kind, n)
end

local function round2(value) return math.floor(value * 100 + 0.5) / 100 end

local function findEntity(id)
    for _, entity in ipairs(creator.draft.entities) do
        if entity.id == id then return entity end
    end
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

-- Adds an entity at the crosshair. The panel sends only a type and a model: the
-- id is generated, the model is checked here, and the new row comes back selected.
local function addEntity(payload)
    local kind = ENTITY_LIMIT_KEY[payload.type] and payload.type or 'prop'
    local model = type(payload.model) == 'string' and payload.model:match('^%s*(.-)%s*$') or ''
    if model == '' or #model > 64 or model:find('[^%w_%-]') then
        updateUi('Enter a model name using letters, numbers and underscores.')
        return
    end
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        updateUi(('"%s" is not a model in the game.'):format(model))
        return
    end
    local count = 0
    for _, entity in ipairs(creator.draft.entities) do if entity.type == kind then count = count + 1 end end
    local limit = Config.sceneLimits[ENTITY_LIMIT_KEY[kind]]
    if limit and count >= limit then
        updateUi(('This scene is at its limit of %d %s entities.'):format(limit, kind))
        return
    end
    local id = nextEntityId(kind)
    local offset = SceneSchema.worldToLocal(creator.draft.anchor, placementPoint())
    creator.draft.entities[#creator.draft.entities + 1] = { id = id, type = kind, model = model, offset = offset }
    if refreshPreview() then updateUi(nil, id) end
end

-- Hands the object to kora_lib's placement tool (surface snap, camera, numeric
-- input, confirm/cancel), then writes the confirmed transform back. The studio's
-- own freecam and NUI focus are released for the duration and restored after,
-- whether the player confirms or cancels.
local function moveEntity(id)
    local entity = not creator.placing and findEntity(id)
    if not entity then return end
    creator.placing = true
    destroyEditorCamera()
    SceneRuntime.cleanupScene()
    SetNuiFocus(false, false)
    updateUi(nil, id)
    local world = SceneSchema.localToWorld(creator.draft.anchor, entity.offset)
    CreateThread(function()
        local ok, result = pcall(function()
            return Kora.placement.start(entity.model, {
                coords = { x = world.x, y = world.y, z = world.z },
                rotation = { pitch = 0.0, roll = 0.0, yaw = world.w },
                copy = false,
            })
        end)
        creator.placing = false
        if not creator.active then return end
        SetNuiFocus(creator.cursor, creator.cursor)
        local failure
        if ok and type(result) == 'table' and result.coords then
            local moved = SceneSchema.worldToLocal(creator.draft.anchor, {
                x = result.coords.x, y = result.coords.y, z = result.coords.z, w = result.heading or world.w,
            })
            entity.offset = { x = round2(moved.x), y = round2(moved.y), z = round2(moved.z), w = round2(moved.w) }
        elseif not ok then
            failure = 'Placement could not start for this model.'
        end
        if refreshPreview() and failure then updateUi(failure) end
    end)
end

local function exportDraft(registerCall)
    local normalized, err = validateDraft()
    if not normalized then updateUi(err); return end
    local definition = SceneSchema.clone(normalized)
    definition.id = nil
    local body = SceneSchema.serializeLua(definition)
    local text
    if registerCall then
        text = ("exports.kora_multichar:RegisterScene(%q, %s)"):format(normalized.id, body)
    else
        text = ("Config.scenes[%q] = %s"):format(normalized.id, body)
    end
    Kora.nui.copyToClipboard(text)
    send('multichar:creator:exported', { registerCall = registerCall })
end

local function closeCreator()
    if not creator.active then return end
    creator.active = false
    destroyEditorCamera()
    SceneRuntime.endMode()
    Kora.callback.trigger('qbmultichar:server:leaveMode')
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
    table.insert(list, destination, table.remove(list, index))
    return true
end

RegisterNetEvent('qbmultichar:client:openCreator', function(catalog)
    if creator.active then return end
    creator.active, creator.catalog, creator.draft = true, catalog or {}, newDraft()
    creator.cursor, creator.camCoords, creator.camRot = true, nil, nil
    SceneRuntime.beginMode()
    SetNuiFocus(true, true)
    send('multichar:creator:show', { draft = creator.draft, scenes = creator.catalog, cursor = true, library = Config.creator.library })
end)

RegisterCommand('qbmultichar_creator_toggle', function()
    if creator.active then setCursor(not creator.cursor) end
end, false)
creatorToggleBinding = Kora.keybind.add({
    name = 'qbmultichar_creator_toggle',
    description = 'Scene Studio: Toggle Cursor / Freecam',
    defaultKey = 'TAB',
    onPressed = function() if creator.active then setCursor(not creator.cursor) end end,
})

RegisterNUICallback('multichar:creator:action', function(data, cb)
    if not creator.active or creator.placing or type(data) ~= 'table' then cb({ ok = false }); return end
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
    elseif action == 'addEntity' then addEntity(payload)
    elseif action == 'moveEntity' then moveEntity(payload.id)
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
        if not creator.cam then
            local started, err = startEditorCamera()
            if not started then updateUi(err); cb({ ok = false }); return end
        end
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
