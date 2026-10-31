-- Data-only scene schema shared by the server registry, client runtime, scene
-- studio and plain-Lua smoke tests. No natives are used in this file.

SceneSchema = SceneSchema or {}

local ALLOWED_ENTITY_TYPES = { ped = true, vehicle = true, prop = true }
local ALLOWED_CUES = {
    camera = true, animation = true, scenario = true, vehicleState = true,
    particle = true, nativeSound = true, entityVisibility = true,
    vehicleRoute = true,
}

local finite = Kora.util.isFiniteNumber

local function array(value)
    if type(value) ~= 'table' then return false end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
        count, maximum = count + 1, math.max(maximum, key)
    end
    return count == maximum
end

local function countByType(entities, wanted)
    local count = 0
    for _, entity in ipairs(entities or {}) do if entity.type == wanted then count = count + 1 end end
    return count
end

local function validOffset(value, requireHeading)
    if value == nil then return false end
    local ok, x, y, z, w = pcall(function() return value.x, value.y, value.z, value.w end)
    if not ok or not finite(x) or not finite(y) or not finite(z) then return false end
    return not requireHeading or finite(w)
end

local function boundedString(value, maximum)
    return type(value) == 'string' and value ~= '' and #value <= maximum and not value:find('[%z\1-\31\127]')
end

local function optionalBoolean(value)
    return value == nil or type(value) == 'boolean'
end

local function dataOnly(value, seen)
    local kind = type(value)
    if kind == 'nil' or kind == 'boolean' then return true end
    if kind == 'number' then return finite(value) end
    if kind == 'string' then return not value:find('[%z\1-\31\127]') end
    if kind == 'vector3' or kind == 'vector4' then return true end
    if kind ~= 'table' then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, child in pairs(value) do
        if not dataOnly(key, seen) or not dataOnly(child, seen) then seen[value] = nil; return false end
    end
    seen[value] = nil
    return true
end

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
    return out
end

function SceneSchema.clone(value)
    return copy(value)
end

---@param id string
---@param scene table
---@param limits table|nil
---@return table|nil, string|nil
function SceneSchema.validate(id, scene, limits)
    limits = limits or Config.sceneLimits
    if type(id) ~= 'string' or not id:match('^[%w_%-]+$') or #id > 48 then return nil, 'scene id must use 1-48 letters, numbers, _ or -' end
    if type(scene) ~= 'table' then return nil, 'scene must be a table' end
    if not dataOnly(scene) then return nil, 'scene definitions must contain only finite data and cannot contain cycles' end
    if not boundedString(scene.label, 64) then return nil, 'scene label is required and capped at 64 bytes' end
    if scene.priority ~= nil and (not finite(scene.priority) or scene.priority % 1 ~= 0) then return nil, 'scene priority must be an integer' end
    if not validOffset(scene.anchor, true) then return nil, 'scene anchor must contain finite x/y/z/w values' end
    if type(scene.character) ~= 'table' or not validOffset(scene.character.offset, true) then return nil, 'scene character.offset is required' end

    if scene.selectors ~= nil and not array(scene.selectors) then return nil, 'scene selectors must be an array' end
    for _, selector in ipairs(scene.selectors or {}) do
        if type(selector) ~= 'table' then return nil, 'each selector must be a table' end
        if selector.job == nil and selector.gang == nil then return nil, 'selector requires job or gang' end
        if selector.job ~= nil and type(selector.job) ~= 'string' then return nil, 'selector job must be a string' end
        if selector.gang ~= nil and type(selector.gang) ~= 'string' then return nil, 'selector gang must be a string' end
        if selector.duty ~= nil and type(selector.duty) ~= 'boolean' then return nil, 'selector duty must be boolean' end
        if selector.minGrade ~= nil and (not finite(selector.minGrade) or selector.minGrade % 1 ~= 0) then return nil, 'selector minGrade must be an integer' end
        if selector.maxGrade ~= nil and (not finite(selector.maxGrade) or selector.maxGrade % 1 ~= 0) then return nil, 'selector maxGrade must be an integer' end
        if selector.minGrade and selector.maxGrade and selector.minGrade > selector.maxGrade then return nil, 'selector grade range is inverted' end
    end


    local environment = scene.environment or {}
    if type(environment) ~= 'table' then return nil, 'scene environment must be a table' end
    if environment.hour ~= nil and (not finite(environment.hour) or environment.hour % 1 ~= 0 or environment.hour < 0 or environment.hour > 23) then return nil, 'environment hour must be 0-23' end
    if environment.minute ~= nil and (not finite(environment.minute) or environment.minute % 1 ~= 0 or environment.minute < 0 or environment.minute > 59) then return nil, 'environment minute must be 0-59' end
    if environment.weather ~= nil and not boundedString(environment.weather, 32) then return nil, 'environment weather is invalid' end
    if environment.timecycle ~= nil and not boundedString(environment.timecycle, 64) then return nil, 'environment timecycle is invalid' end
    if environment.strength ~= nil and (not finite(environment.strength) or environment.strength < 0 or environment.strength > 1) then return nil, 'environment strength must be 0-1' end

    local character = scene.character or {}
    if character.scenario ~= nil and not boundedString(character.scenario, 96) then return nil, 'character scenario is invalid' end
    if character.animation ~= nil then
        if type(character.animation) ~= 'table' or not boundedString(character.animation.dict, 128) or not boundedString(character.animation.name, 128) then
            return nil, 'character animation requires dict and name'
        end
    end

    if not array(scene.entities or {}) then return nil, 'scene entities must be an array' end
    if countByType(scene.entities, 'ped') > limits.maxPeds then return nil, 'scene exceeds ped limit' end
    if countByType(scene.entities, 'vehicle') > limits.maxVehicles then return nil, 'scene exceeds vehicle limit' end
    if countByType(scene.entities, 'prop') > limits.maxProps then return nil, 'scene exceeds prop limit' end
    local entityIds, entityTypes, seatedPeds, seatedPedIds = {}, {}, {}, {}
    for _, entity in ipairs(scene.entities or {}) do
        if type(entity) ~= 'table' or not ALLOWED_ENTITY_TYPES[entity.type] then return nil, 'entity type must be ped, vehicle, or prop' end
        if not boundedString(entity.id, 48) or entityIds[entity.id] then return nil, 'entity ids must be 1-48 visible bytes and unique' end
        if type(entity.model) ~= 'string' and type(entity.model) ~= 'number' then return nil, ('entity %s requires a model'):format(entity.id) end
        if not validOffset(entity.offset, true) then return nil, ('entity %s has an invalid offset'):format(entity.id) end
        if not optionalBoolean(entity.collision) or not optionalBoolean(entity.frozen) or not optionalBoolean(entity.snapToGround) or not optionalBoolean(entity.snapToWater) then return nil, ('entity %s has invalid flags'):format(entity.id) end
        if entity.snapToWater == true and entity.type ~= 'vehicle' then return nil, ('entity %s can only snap vehicles to water'):format(entity.id) end
        if entity.scenario ~= nil and not boundedString(entity.scenario, 96) then return nil, ('entity %s has an invalid scenario'):format(entity.id) end
        if entity.animation ~= nil and (type(entity.animation) ~= 'table' or not boundedString(entity.animation.dict, 128) or not boundedString(entity.animation.name, 128)) then
            return nil, ('entity %s has an invalid animation'):format(entity.id)
        end
        if entity.vehicle ~= nil then
            if entity.type ~= 'vehicle' or type(entity.vehicle) ~= 'table' then return nil, ('entity %s has invalid vehicle state'):format(entity.id) end
            local vehicle = entity.vehicle
            if not optionalBoolean(vehicle.engine) or not optionalBoolean(vehicle.lights) or not optionalBoolean(vehicle.siren) or not optionalBoolean(vehicle.mutedSiren) or not optionalBoolean(vehicle.anchored) then
                return nil, ('entity %s has invalid vehicle flags'):format(entity.id)
            end
            if vehicle.livery ~= nil and (not finite(vehicle.livery) or vehicle.livery % 1 ~= 0) then return nil, ('entity %s has invalid livery'):format(entity.id) end
            for _, color in ipairs({ 'primaryColor', 'secondaryColor' }) do
                if vehicle[color] ~= nil and (not finite(vehicle[color]) or vehicle[color] % 1 ~= 0 or vehicle[color] < 0 or vehicle[color] > 255) then
                    return nil, ('entity %s has an invalid vehicle color'):format(entity.id)
                end
            end
            if vehicle.extras ~= nil and type(vehicle.extras) ~= 'table' then return nil, ('entity %s extras must be a table'):format(entity.id) end
            if vehicle.doors ~= nil and type(vehicle.doors) ~= 'table' then return nil, ('entity %s doors must be a table'):format(entity.id) end
        end
        if entity.seat ~= nil then
            if entity.type ~= 'ped' or type(entity.seat) ~= 'table' or not boundedString(entity.seat.vehicle, 48) then
                return nil, ('entity %s has an invalid vehicle seat'):format(entity.id)
            end
            local seatIndex = entity.seat.index
            if not finite(seatIndex) or seatIndex % 1 ~= 0 or seatIndex < -1 or seatIndex > 6 then
                return nil, ('entity %s has an invalid seat index'):format(entity.id)
            end
            seatedPeds[#seatedPeds + 1] = { id = entity.id, vehicle = entity.seat.vehicle }
            seatedPedIds[entity.id] = true
        end
        entityIds[entity.id], entityTypes[entity.id] = true, entity.type
    end
    for _, seated in ipairs(seatedPeds) do
        if entityTypes[seated.vehicle] ~= 'vehicle' then
            return nil, ('entity %s seat references an unknown vehicle'):format(seated.id)
        end
    end

    if not array(scene.cameras or {}) or #(scene.cameras or {}) < 1 then return nil, 'scene requires at least one camera' end
    if #scene.cameras > limits.maxCameras then return nil, 'scene exceeds camera limit' end
    local cameraIds = {}
    for _, camera in ipairs(scene.cameras) do
        if type(camera) ~= 'table' or not boundedString(camera.id, 48) or cameraIds[camera.id] then return nil, 'camera ids must be 1-48 visible bytes and unique' end
        if not validOffset(camera.offset) or not validOffset(camera.lookAt) then return nil, ('camera %s requires offset and lookAt'):format(camera.id) end
        if camera.fov ~= nil and (not finite(camera.fov) or camera.fov < 10 or camera.fov > 100) then return nil, ('camera %s has invalid fov'):format(camera.id) end
        if camera.durationMs ~= nil and (not finite(camera.durationMs) or camera.durationMs < 0 or camera.durationMs > limits.maxTimelineMs) then return nil, ('camera %s has invalid duration'):format(camera.id) end
        if camera.transitionMs ~= nil and (not finite(camera.transitionMs) or camera.transitionMs < 0 or camera.transitionMs > 10000) then return nil, ('camera %s has invalid transition'):format(camera.id) end
        if camera.dof ~= nil then
            if type(camera.dof) ~= 'table' then return nil, ('camera %s has invalid depth of field'):format(camera.id) end
            for _, field in ipairs({ 'near', 'far', 'strength' }) do
                if camera.dof[field] ~= nil and not finite(camera.dof[field]) then return nil, ('camera %s has invalid depth of field'):format(camera.id) end
            end
        end
        cameraIds[camera.id] = true
    end

    local timeline = scene.timeline or {}
    if type(timeline) ~= 'table' then return nil, 'scene timeline must be a table' end
    if timeline.durationMs ~= nil and (not finite(timeline.durationMs) or timeline.durationMs < 0 or timeline.durationMs > limits.maxTimelineMs) then return nil, 'timeline duration exceeds limit' end
    if timeline.loop ~= nil and type(timeline.loop) ~= 'boolean' then return nil, 'timeline loop must be boolean' end
    if not array(timeline.cues or {}) then return nil, 'timeline cues must be an array' end
    if #(timeline.cues or {}) > limits.maxCues then return nil, 'scene exceeds timeline cue limit' end
    for _, cue in ipairs(timeline.cues or {}) do
        if type(cue) ~= 'table' or not ALLOWED_CUES[cue.type] then return nil, 'timeline contains an unsupported cue type' end
        if not finite(cue.at or 0) or (cue.at or 0) < 0 or (timeline.durationMs and cue.at > timeline.durationMs) then return nil, 'timeline cue time is invalid' end
        if cue.type == 'camera' and not cameraIds[cue.camera] then return nil, 'camera cue references an unknown camera' end
        if cue.transitionMs ~= nil and (not finite(cue.transitionMs) or cue.transitionMs < 0 or cue.transitionMs > 10000) then return nil, 'cue transition is invalid' end
        if cue.target and cue.target ~= 'character' and not entityIds[cue.target] then return nil, ('cue references unknown target %s'):format(cue.target) end
        if cue.durationMs ~= nil and (not finite(cue.durationMs) or cue.durationMs < 0 or cue.durationMs > limits.maxTimelineMs) then return nil, 'cue duration is invalid' end
        if cue.type == 'animation' and (not cue.target or not boundedString(cue.dict, 128) or not boundedString(cue.name, 128)) then return nil, 'animation cue requires target, dict, and name' end
        if cue.type == 'scenario' and (not cue.target or (cue.name ~= nil and not boundedString(cue.name, 96))) then return nil, 'scenario cue requires a valid target and name' end
        if cue.type == 'vehicleState' then
            if entityTypes[cue.target] ~= 'vehicle' then return nil, 'vehicleState cue must target a vehicle' end
            if not optionalBoolean(cue.engine) or not optionalBoolean(cue.lights) or not optionalBoolean(cue.siren) or not optionalBoolean(cue.mutedSiren) or not optionalBoolean(cue.anchored) then return nil, 'vehicleState cue has invalid flags' end
            if cue.livery ~= nil and (not finite(cue.livery) or cue.livery % 1 ~= 0) then return nil, 'vehicleState cue has invalid livery' end
            for _, color in ipairs({ 'primaryColor', 'secondaryColor' }) do
                if cue[color] ~= nil and (not finite(cue[color]) or cue[color] % 1 ~= 0 or cue[color] < 0 or cue[color] > 255) then return nil, 'vehicleState cue has an invalid color' end
            end
            if cue.extras ~= nil and type(cue.extras) ~= 'table' then return nil, 'vehicleState extras must be a table' end
            if cue.doors ~= nil and type(cue.doors) ~= 'table' then return nil, 'vehicleState doors must be a table' end
        end
        if cue.type == 'vehicleRoute' then
            if entityTypes[cue.target] ~= 'ped' or not seatedPedIds[cue.target] then
                return nil, 'vehicleRoute cue must target a seated driver ped'
            end
            if not validOffset(cue.destination) then return nil, 'vehicleRoute cue requires a destination offset' end
            if cue.speed ~= nil and (not finite(cue.speed) or cue.speed <= 0 or cue.speed > 80) then return nil, 'vehicleRoute speed must be 0-80' end
            if cue.drivingStyle ~= nil and (not finite(cue.drivingStyle) or cue.drivingStyle % 1 ~= 0 or cue.drivingStyle < 0 or cue.drivingStyle > 2147483647) then return nil, 'vehicleRoute drivingStyle must be a bounded positive integer' end
            if cue.stoppingRange ~= nil and (not finite(cue.stoppingRange) or cue.stoppingRange < 0 or cue.stoppingRange > 100) then return nil, 'vehicleRoute stoppingRange must be 0-100' end
            if not optionalBoolean(cue.snapToGround) or not optionalBoolean(cue.snapToWater) or (cue.snapToGround == true and cue.snapToWater == true) then return nil, 'vehicleRoute must choose at most one destination surface' end
        end
        if cue.type == 'particle' then
            if not boundedString(cue.asset, 96) or not boundedString(cue.effect, 96) then return nil, 'particle cue requires asset and effect' end
            if cue.scale ~= nil and (not finite(cue.scale) or cue.scale <= 0 or cue.scale > 20) then return nil, 'particle cue scale is invalid' end
            if cue.offset ~= nil and not validOffset(cue.offset) then return nil, 'particle cue offset is invalid' end
        end
        if cue.type == 'nativeSound' and (not boundedString(cue.name, 96) or (cue.set ~= nil and not boundedString(cue.set, 96))) then return nil, 'nativeSound cue requires a native sound name and set' end
        if cue.type == 'entityVisibility' and (not cue.target or not optionalBoolean(cue.visible)) then return nil, 'entityVisibility cue requires a target and boolean visibility' end
    end

    local normalized = copy(scene)
    normalized.id = id
    normalized.priority = math.floor(scene.priority or 0)
    normalized.enabled = scene.enabled ~= false
    normalized.entities = normalized.entities or {}
    normalized.selectors = normalized.selectors or {}
    normalized.timeline = normalized.timeline or { durationMs = 0, loop = false, cues = {} }
    normalized.timeline.cues = normalized.timeline.cues or {}
    table.sort(normalized.timeline.cues, function(a, b)
        if (a.at or 0) == (b.at or 0) then return tostring(a.type) < tostring(b.type) end
        return (a.at or 0) < (b.at or 0)
    end)
    return normalized
end

local function selectorMatches(selector, character)
    local job, gang = character.job or {}, character.gang or {}
    if selector.job and selector.job ~= job.name then return false end
    if selector.gang and selector.gang ~= gang.name then return false end
    local gradeSource = selector.job and job or gang
    local grade = tonumber(gradeSource.grade and gradeSource.grade.level) or 0
    if selector.minGrade and grade < selector.minGrade then return false end
    if selector.maxGrade and grade > selector.maxGrade then return false end
    if selector.duty ~= nil and (job.onduty == true) ~= selector.duty then return false end
    return true
end

function SceneSchema.matches(scene, character)
    for _, selector in ipairs(scene.selectors or {}) do
        if selectorMatches(selector, character) then return true end
    end
    return false
end

function SceneSchema.resolve(scenes, character, defaultId)
    local matches = {}
    for id, scene in pairs(scenes or {}) do
        if scene.enabled ~= false and SceneSchema.matches(scene, character or {}) then
            matches[#matches + 1] = { id = id, scene = scene }
        end
    end
    table.sort(matches, function(a, b)
        local pa, pb = a.scene.priority or 0, b.scene.priority or 0
        if pa == pb then return a.id < b.id end
        return pa > pb
    end)
    if matches[1] then return matches[1].scene, matches[1].id end

    -- No selector matched: an unemployed character, or any job/gang nobody has
    -- authored a scene for. The configured default covers both.
    local fallback = scenes and scenes[defaultId]
    if fallback then return fallback, defaultId end

    -- The default itself is missing -- a misconfigured Config.defaultScene, or
    -- a default scene the registry rejected. Returning nil here is worse than
    -- it looks: every caller's own retry chain re-resolves through this same
    -- default, so one missing scene fails three times over and leaves the
    -- player on a black screen. Any usable scene beats that, chosen by id so
    -- the choice is deterministic rather than pairs() order.
    if scenes then
        local ids = {}
        for id, scene in pairs(scenes) do
            if scene.enabled ~= false then ids[#ids + 1] = id end
        end
        table.sort(ids)
        if ids[1] then return scenes[ids[1]], ids[1] end
    end
    return nil, defaultId
end

function SceneSchema.localToWorld(anchor, offset)
    local radians = math.rad(anchor.w or 0.0)
    local cosH, sinH = math.cos(radians), math.sin(radians)
    return {
        x = anchor.x + offset.x * cosH - offset.y * sinH,
        y = anchor.y + offset.x * sinH + offset.y * cosH,
        z = anchor.z + offset.z,
        w = ((anchor.w or 0.0) + (offset.w or 0.0)) % 360.0,
    }
end

function SceneSchema.worldToLocal(anchor, world)
    local radians = math.rad(-(anchor.w or 0.0))
    local cosH, sinH = math.cos(radians), math.sin(radians)
    local dx, dy = world.x - anchor.x, world.y - anchor.y
    return {
        x = dx * cosH - dy * sinH,
        y = dx * sinH + dy * cosH,
        z = world.z - anchor.z,
        w = ((world.w or 0.0) - (anchor.w or 0.0)) % 360.0,
    }
end

local function isArray(value)
    if type(value) ~= 'table' then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
        count = math.max(count, key)
    end
    return count == #value
end

local function rounded(value)
    local result
    if value >= 0 then result = math.floor(value * 1000 + 0.5) / 1000
    else result = math.ceil(value * 1000 - 0.5) / 1000 end
    return result == 0 and 0 or result
end

local function vectorParts(value)
    if value == nil then return nil end
    local ok, x, y, z, w = pcall(function() return value.x, value.y, value.z, value.w end)
    if ok and finite(x) and finite(y) and finite(z) then return x, y, z, w end
end

---Deterministic scene-studio Lua serialization: stable map ordering and
---three-decimal transforms. Definitions are validated before this is called.
function SceneSchema.serializeLua(value, indent)
    indent = indent or 0
    local x, y, z, w = vectorParts(value)
    if x then
        x, y, z = rounded(x), rounded(y), rounded(z)
        if w ~= nil then return ('vector4(%.3f, %.3f, %.3f, %.3f)'):format(x, y, z, rounded(w)) end
        return ('vector3(%.3f, %.3f, %.3f)'):format(x, y, z)
    end
    if type(value) == 'string' then return string.format('%q', value) end
    if type(value) == 'number' then return tostring(rounded(value)) end
    if type(value) == 'boolean' or value == nil then return tostring(value) end
    if type(value) ~= 'table' then return 'nil' end

    local pad, nextPad = string.rep(' ', indent), string.rep(' ', indent + 4)
    local parts = { '{' }
    if isArray(value) then
        for _, child in ipairs(value) do
            parts[#parts + 1] = ('\n%s%s,'):format(nextPad, SceneSchema.serializeLua(child, indent + 4))
        end
    else
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do
            local renderedKey = type(key) == 'string' and key:match('^[%a_][%w_]*$') and key
                or ('[%s]'):format(SceneSchema.serializeLua(key))
            parts[#parts + 1] = ('\n%s%s = %s,'):format(nextPad, renderedKey, SceneSchema.serializeLua(value[key], indent + 4))
        end
    end
    if #parts > 1 then parts[#parts + 1] = '\n' .. pad .. '}' else parts[#parts + 1] = '}' end
    return table.concat(parts)
end
