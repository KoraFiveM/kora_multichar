local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local root = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')

local function vector(x, y, z, w)
    local result = { x = x, y = y, z = z }
    if w ~= nil then result.w = w end
    return result
end
_G.vector3 = function(x, y, z) return vector(x, y, z) end
_G.vector4 = function(x, y, z, w) return vector(x, y, z, w) end
_G.QB = { util = { isFiniteNumber = function(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end } }

dofile(root .. 'config.lua')
dofile(root .. 'shared/scene.lua')
dofile(root .. 'scenes.lua')

local function character(job, jobGrade, gang, gangGrade, duty)
    return {
        job = { name = job or 'unemployed', grade = { level = jobGrade or 0 }, onduty = duty },
        gang = { name = gang or 'none', grade = { level = gangGrade or 0 } },
    }
end

local function validatedCatalog()
    local catalog = {}
    for id, scene in pairs(Config.scenes) do
        local normalized, err = SceneSchema.validate(id, scene, Config.sceneLimits)
        H.truthy(normalized, ('bundled scene %s should validate: %s'):format(id, tostring(err)))
        catalog[id] = normalized
    end
    return catalog
end

H.test('all six bundled scenes pass the shared schema', function()
    local catalog, count = validatedCatalog(), 0
    for _ in pairs(catalog) do count = count + 1 end
    H.equal(count, 6, 'bundled scene count')
end)

H.test('every bundled scene runs portrait, focal, establishing, focal, portrait', function()
    for id, scene in pairs(Config.scenes) do
        H.equal(scene.cameras[1].id, 'close', id .. ' should open with its portrait camera')
        H.equal(scene.timeline.cues[1].camera, 'close', id .. ' timeline should begin on the portrait')
        local cameraSequence = {}
        for _, cue in ipairs(scene.timeline.cues) do
            if cue.type == 'camera' then cameraSequence[#cameraSequence + 1] = cue.camera end
        end
        H.equal(table.concat(cameraSequence, ','), 'close,focal,establishing,focal,close', id .. ' should use the complete camera arc')
        H.equal(scene.cameras[3].id, 'establishing', id .. ' should contain a wider establishing camera')
        H.truthy(scene.cameras[3].fov > scene.cameras[2].fov, id .. ' establishing shot should be wider than focal')
    end
    H.truthy(Config.scenes.police.label:lower():find('robbery', 1, true), 'police scene should be a robbery response')
    H.truthy(Config.scenes.police.anchor.x < 0, 'police scene should no longer use the Mission Row anchor')
end)

H.test('civilian scene is a seated-rider beach composition', function()
    local scene, vehicles, seated, routes = Config.scenes.civilian, 0, 0, 0
    H.truthy(scene.label:lower():find('beach', 1, true), 'civilian scene should be on the beach')
    H.truthy(scene.anchor.x >= -1582.03 and scene.anchor.x <= -1549.01
        and scene.anchor.y >= -1199.60 and scene.anchor.y <= -1162.08,
        'civilian character anchor should remain inside the dry Vespucci beach strip')
    for _, entity in ipairs(scene.entities) do
        if entity.type == 'vehicle' and entity.model:find('seashark', 1, true) then
            vehicles = vehicles + 1
            H.truthy(entity.snapToWater == true, 'jet skis should resolve against the water surface')
            H.truthy(entity.frozen == false and entity.collision == true, 'driven jet skis must be mobile with collision')
            H.falsy(entity.vehicle.anchored, 'driven jet skis must not be anchored')
        end
        if entity.type == 'ped' and entity.seat then seated = seated + 1 end
    end
    for _, cue in ipairs(scene.timeline.cues) do
        if cue.type == 'vehicleRoute' then routes = routes + 1 end
    end
    H.equal(vehicles, 2, 'beach scene jet ski count')
    H.equal(seated, 2, 'beach scene seated rider count')
    H.equal(routes, 4, 'both riders should receive outbound and return routes')
end)

H.test('ambulance scene is an outdoor active paramedic response', function()
    local scene, ambulance, medicalPeds, hasPatient, hasStretcher = Config.scenes.ambulance, nil, 0, false, false
    H.truthy(scene.label:lower():find('active medical response', 1, true), 'EMS label should describe an active response')
    for _, entity in ipairs(scene.entities) do
        if entity.id == 'ambulance' then ambulance = entity end
        if entity.model == 's_m_m_paramedic_01' then medicalPeds = medicalPeds + 1 end
        if entity.id == 'patient' then hasPatient = true end
        if entity.id == 'stretcher' then hasStretcher = true end
    end
    H.truthy(ambulance, 'EMS scene needs an ambulance')
    local ambulanceWorld = SceneSchema.localToWorld(scene.anchor, ambulance.offset)
    H.close(ambulanceWorld.x, 294.59, 0.2, 'ambulance should use the outdoor Pillbox vehicle bay x')
    H.close(ambulanceWorld.y, -574.77, 0.2, 'ambulance should use the outdoor Pillbox vehicle bay y')
    H.truthy(ambulance.vehicle.doors[2] and ambulance.vehicle.doors[3], 'ambulance rear doors should be staged open')
    H.equal(medicalPeds, 2, 'EMS scene supporting paramedic count')
    H.truthy(hasPatient and hasStretcher, 'EMS response should include a patient and stretcher')
    H.equal(scene.character.animation.name, 'cpr_pumpchest', 'selected EMS character should actively perform CPR')
end)

H.test('selectors are OR alternatives and fields inside one selector are AND conditions', function()
    local scene = SceneSchema.clone(Config.scenes.police)
    scene.selectors = {
        { job = 'police', gang = 'ballas', minGrade = 2, maxGrade = 4, duty = true },
        { job = 'ambulance', minGrade = 1 },
    }
    local normalized = assert(SceneSchema.validate('selector_test', scene, Config.sceneLimits))
    H.truthy(SceneSchema.matches(normalized, character('police', 3, 'ballas', 0, true)), 'all fields in first alternative match')
    H.falsy(SceneSchema.matches(normalized, character('police', 3, 'vagos', 0, true)), 'gang mismatch rejects the first alternative')
    H.falsy(SceneSchema.matches(normalized, character('police', 1, 'ballas', 5, true)), 'grade range applies to the selected job')
    H.falsy(SceneSchema.matches(normalized, character('police', 3, 'ballas', 0, false)), 'explicit duty mismatch rejects')
    H.truthy(SceneSchema.matches(normalized, character('ambulance', 2, 'none', 0, false)), 'second alternative matches independently')
end)

H.test('priority wins over gang, ties use scene id, and fallback is deterministic', function()
    local catalog = validatedCatalog()
    local scene, id = SceneSchema.resolve(catalog, character('police', 4, 'ballas', 2, false), Config.defaultScene)
    H.equal(id, 'police', 'career priority 200 should beat gang priority 100')
    H.equal(scene.label, 'Strawberry 24/7 · Robbery in Progress', 'resolved police scene')

    local a = assert(SceneSchema.validate('alpha', Config.scenes.police, Config.sceneLimits))
    local z = assert(SceneSchema.validate('zulu', Config.scenes.police, Config.sceneLimits))
    local _, tieId = SceneSchema.resolve({ zulu = z, alpha = a, civilian = catalog.civilian }, character('police', 0), 'civilian')
    H.equal(tieId, 'alpha', 'lexicographically smallest id breaks equal priority ties')

    local fallback, fallbackId = SceneSchema.resolve(catalog, character('taxi', 0, 'none', 0), Config.defaultScene)
    H.equal(fallbackId, 'civilian', 'unmatched character uses configured fallback')
    H.equal(fallback.id, 'civilian', 'fallback carries normalized id')
end)

-- The default scene serves two roles and has to hold up in both: the explicit
-- scene for an unemployed character, and the fallback for any job or gang
-- nobody has authored a scene for.
H.test('the default scene covers unemployed explicitly and unconfigured jobs by fallback', function()
    local catalog = validatedCatalog()

    H.truthy(SceneSchema.matches(catalog.civilian, character('unemployed', 0)),
        'unemployed must MATCH the default scene, not merely fall through to it')
    local _, unemployedId = SceneSchema.resolve(catalog, character('unemployed', 0), Config.defaultScene)
    H.equal(unemployedId, 'civilian', 'unemployed resolves to the default scene')

    -- Priority 0 keeps it the lowest bidder, so an unemployed gang member still
    -- gets their gang's scene rather than the default.
    local _, gangId = SceneSchema.resolve(catalog, character('unemployed', 0, 'ballas', 1), Config.defaultScene)
    H.equal(gangId, 'ballas', 'a configured gang scene still outranks the default')

    -- A missing default used to return nil, which fails the caller's whole
    -- retry chain (every attempt re-resolves through this same default) and
    -- leaves the player on a black screen.
    local without = {}
    for id, scene in pairs(catalog) do if id ~= 'civilian' then without[id] = scene end end
    local orphan, orphanId = SceneSchema.resolve(without, character('taxi', 0), 'civilian')
    H.truthy(orphan, 'a missing default must still resolve to some usable scene')
    H.equal(orphanId, 'ambulance', 'the substitute is chosen by id, so it is deterministic')

    local none, noneId = SceneSchema.resolve({}, character('unemployed', 0), 'civilian')
    H.falsy(none, 'a genuinely empty catalog still resolves to nothing')
    H.equal(noneId, 'civilian', 'and reports the id it wanted')
end)

H.test('relative transforms rotate around a relocatable world anchor', function()
    local anchor = vector4(100.0, 200.0, 30.0, 90.0)
    local world = SceneSchema.localToWorld(anchor, vector4(2.0, 1.0, 3.0, 15.0))
    H.close(world.x, 99.0, 0.0001, 'rotated x')
    H.close(world.y, 202.0, 0.0001, 'rotated y')
    H.close(world.z, 33.0, 0.0001, 'translated z')
    H.close(world.w, 105.0, 0.0001, 'composed heading')
    local localAgain = SceneSchema.worldToLocal(anchor, world)
    H.close(localAgain.x, 2.0, 0.0001, 'inverse x')
    H.close(localAgain.y, 1.0, 0.0001, 'inverse y')
    H.close(localAgain.z, 3.0, 0.0001, 'inverse z')
    H.close(localAgain.w, 15.0, 0.0001, 'inverse heading')
end)

H.test('schema rejects missing cameras, invalid references, and configured limits', function()
    local scene = SceneSchema.clone(Config.scenes.civilian)
    scene.cameras = {}
    local valid, err = SceneSchema.validate('bad_camera', scene, Config.sceneLimits)
    H.falsy(valid, 'a character scene without cameras must fail')
    H.truthy(err:find('camera', 1, true), 'camera error should be descriptive')

    scene = SceneSchema.clone(Config.scenes.civilian)
    scene.timeline.cues[1].camera = 'missing'
    valid, err = SceneSchema.validate('bad_reference', scene, Config.sceneLimits)
    H.falsy(valid, 'unknown camera cue must fail')
    H.truthy(err:find('unknown camera', 1, true), 'reference error should be descriptive')

    scene = SceneSchema.clone(Config.scenes.civilian)
    scene.timeline.durationMs = Config.sceneLimits.maxTimelineMs + 1
    valid = SceneSchema.validate('too_long', scene, Config.sceneLimits)
    H.falsy(valid, 'timeline over 120 seconds must fail')

    scene = SceneSchema.clone(Config.scenes.civilian)
    scene.entities = {}
    for index = 1, Config.sceneLimits.maxPeds + 1 do
        scene.entities[index] = { id = 'ped_' .. index, type = 'ped', model = 'a_m_y_business_02', offset = vector4(index, 0, 0, 0) }
    end
    valid = SceneSchema.validate('too_many_peds', scene, Config.sceneLimits)
    H.falsy(valid, 'ped count over the configured cap must fail')

    scene = SceneSchema.clone(Config.scenes.civilian)
    scene.unsafe = function() end
    valid = SceneSchema.validate('not_data', scene, Config.sceneLimits)
    H.falsy(valid, 'scene definitions containing executable values must fail')

    scene = SceneSchema.clone(Config.scenes.civilian)
    scene.entities[3].seat.vehicle = 'missing_jetski'
    valid, err = SceneSchema.validate('bad_seat', scene, Config.sceneLimits)
    H.falsy(valid, 'a rider cannot reference a missing vehicle')
    H.truthy(err:find('seat', 1, true), 'seat reference error should be descriptive')

    scene = SceneSchema.clone(Config.scenes.civilian)
    for _, cue in ipairs(scene.timeline.cues) do
        if cue.type == 'vehicleRoute' then cue.target = 'walker'; break end
    end
    valid, err = SceneSchema.validate('bad_route_driver', scene, Config.sceneLimits)
    H.falsy(valid, 'vehicle routes must target a seated driver')
    H.truthy(err:find('seated driver', 1, true), 'vehicle route target error should be descriptive')
end)

H.test('studio serialization is deterministic, rounded, and preserves nested stable ids', function()
    local left = {
        zeta = 2,
        anchor = vector4(1.23456, -2.34555, 3.0, 90.0),
        entities = { { model = 'sultan', id = 'project', type = 'vehicle' } },
        alpha = 1,
    }
    local right = {
        alpha = 1,
        entities = { { type = 'vehicle', id = 'project', model = 'sultan' } },
        anchor = vector4(1.23456, -2.34555, 3.0, 90.0),
        zeta = 2,
    }
    local a, b = SceneSchema.serializeLua(left), SceneSchema.serializeLua(right)
    H.equal(a, b, 'map insertion order must not affect exported Lua')
    H.truthy(a:find('id = "project"', 1, true), 'nested entity ids must be retained')
    H.truthy(a:find('vector4(1.235, -2.346, 3.000, 90.000)', 1, true), 'coordinates must round to three decimals')
    H.truthy(a:find('alpha', 1, true) < a:find('zeta', 1, true), 'map keys must be sorted')
end)

H.report('scenes')
