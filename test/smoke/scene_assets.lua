-- Actual SceneRuntime/schema and kora_lib stream/loop APIs; all native boundaries
-- are controlled recorders. Release calls are measured, not native memory,
-- animation/FX geometry, or real engine ownership/reference-count behavior.
-- Run with test/run.sh; optional arguments: resource root, support root, scene source.
local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local root = arg[1] or scriptDir .. '../../'
local support = arg[2] or root
if root:sub(-1) ~= '/' then root = root .. '/' end
if support:sub(-1) ~= '/' then support = support .. '/' end
local kora_lib = support .. '../kora_lib/'
package.path = support .. 'test/?.lua;' .. package.path
local H = require('harness')
local scenePath = arg[3] or root .. 'scene.lua'
local checks = 0
local function eq(value, expected, label)
    H.equal(value, expected, label)
    checks = checks + 1
end
local function read(path) local f = assert(io.open(path, 'rb')); local value = f:read('*a'); f:close(); return value end
local source = read(scenePath)
local noop = function() end
local world
local function count(kind, key)
    local n = 0; for _, call in ipairs(world.calls) do if call.kind == kind and (key == nil or call.key == key) then n = n + 1 end end; return n
end
local function record(kind, key) world.calls[#world.calls + 1] = { kind = kind, key = key } end
local function fresh()
    world = { entities = { [1] = true }, nextEntity = 1, nextCam = 100, cameras = {}, nextFx = 200, fx = {},
        anim = {}, ptfx = {}, heldAnim = {}, heldPtfx = {}, calls = {}, handlers = {}, threads = {}, timer = 0 }
    Kora = { stream = {}, util = {}, loops = {}, compat = { isCallable = function(v) return type(v) == 'function' end } }
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end
    vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
    joaat = function(name) local hash = 1000; for index = 1, #name do hash = hash + name:byte(index) end; return hash end
    GetGameTimer = function() return world.timer end
    Wait = function(ms) world.timer = world.timer + math.max(ms or 0, 1); coroutine.yield('wait') end
    CreateThread = function(fn) world.threads[#world.threads + 1] = coroutine.create(fn) end
    SetTimeout = function() end -- duration callbacks remain inert; explicit cleanup is under test.
    AddEventHandler = function(name, fn) world.handlers[name] = fn end
    GetCurrentResourceName = function() return 'kora_multichar' end
    IsModelValid, HasModelLoaded = function() return true end, function() return true end
    RequestModel, SetModelAsNoLongerNeeded = noop, noop
    DoesAnimDictExist = function(name) return name ~= 'invalid_dict' end
    HasAnimDictLoaded = function(name) return world.anim[name] == true end
    RequestAnimDict = function(name) record('request-anim', name); if not world.heldAnim[name] then world.anim[name] = true end end
    RemoveAnimDict = function(name) record('remove-anim', name) end
    HasNamedPtfxAssetLoaded = function(name) return world.ptfx[name] == true end
    RequestNamedPtfxAsset = function(name) record('request-ptfx', name); if not world.heldPtfx[name] then world.ptfx[name] = true end end
    RemoveNamedPtfxAsset = function(name) record('remove-ptfx', name) end
    PlayerPedId, PlayerId = function() return 1 end, function() return 0 end
    DoesEntityExist = function(id) return world.entities[id] == true end
    GetEntityCoords = function() return vector3(0, 0, 0) end
    GetEntityHeading = function() return 0 end
    CreatePed = function() world.nextEntity = world.nextEntity + 1; world.entities[world.nextEntity] = true; return world.nextEntity end
    DeleteEntity = function(id) record('delete-entity', id); world.entities[id] = nil end
    TaskPlayAnim = function(ped, dict) record('play-anim', dict); record('animate-ped', ped) end
    TaskStartScenarioInPlace, ClearPedTasks, ClearPedTasksImmediately = noop, noop, noop
    GetResourceState = function() return 'missing' end
    IsScreenFadedOut = function() return true end
    IsNewLoadSceneActive = function() return false end
    NewLoadSceneStartSphere, HasCollisionLoadedAroundEntity = function() return true end, function() return true end
    GetGroundZFor_3dCoord, GetWaterHeight = function() return false end, function() return false end
    StartShapeTestCapsule = function() return 42 end
    GetShapeTestResult = function() return 2, false, nil end
    CreateCam = function() world.nextCam = world.nextCam + 1; world.cameras[world.nextCam] = true; return world.nextCam end
    DoesCamExist = function(cam) return world.cameras[cam] == true end
    DestroyCam = function(cam) world.cameras[cam] = nil end
    StartParticleFxLoopedOnEntity = function(_, target)
        eq(world.entities[target], true, 'FX starts only on a live scene entity')
        world.nextFx = world.nextFx + 1; world.fx[world.nextFx] = true; record('start-fx', world.nextFx); return world.nextFx
    end
    StartParticleFxLoopedAtCoord = function()
        world.nextFx = world.nextFx + 1; world.fx[world.nextFx] = true; record('start-fx', world.nextFx); return world.nextFx
    end
    StopParticleFxLooped = function(fx) world.fx[fx] = nil; record('stop-fx', fx) end
    for _, name in ipairs({ 'RequestCollisionAtCoord', 'NewLoadSceneStop', 'SetEntityCoordsNoOffset', 'FreezeEntityPosition',
        'SetEntityCollision', 'SetEntityVisible', 'SetFocusEntity', 'SetEntityAsMissionEntity', 'SetEntityInvincible',
        'SetBlockingOfNonTemporaryEvents', 'SetCamCoord', 'PointCamAtCoord', 'SetCamFov', 'SetCamActive', 'RenderScriptCams',
        'SetCamActiveWithInterp', 'ClearFocus', 'ClearOverrideWeather', 'ClearWeatherTypePersist', 'NetworkClearClockTimeOverride',
        'ClearTimecycleModifier', 'DoScreenFadeIn', 'DoScreenFadeOut', 'UseParticleFxAssetNextCall', 'SetEntityHeading',
        'SetCamUseShallowDofMode', 'SetCamNearDof', 'SetCamFarDof', 'SetCamDofStrength', 'NetworkOverrideClockTime',
        'SetWeatherTypeNow', 'SetWeatherTypeNowPersist', 'SetTimecycleModifier', 'SetTimecycleModifierStrength' }) do _G[name] = noop end
    dofile(kora_lib .. 'modules/util/shared.lua')
    dofile(kora_lib .. 'modules/loops/shared.lua')
    dofile(kora_lib .. 'modules/stream/client.lua')
    dofile(root .. 'config.lua')
    Config.sceneLimits.streamTimeoutMs = 10
    dofile(root .. 'shared/scene.lua')
    SceneRuntime = nil
    assert(load(source, '@' .. scenePath))()
end
local function definition(dict, extra)
    return assert(SceneSchema.validate('fixture', {
        label = 'Synthetic scene', anchor = vector4(0, 0, 0, 0),
        character = { offset = vector4(0, 0, 0, 0), animation = dict and { dict = dict, name = 'fixture_anim' } or nil },
        entities = extra or {}, cameras = { { id = 'close', offset = vector3(3, -4, 2), lookAt = vector3(0, 0, 1), fov = 40 } },
        timeline = { durationMs = 0, cues = {} },
    }, Config.sceneLimits))
end
local function show(dict, extra) eq(SceneRuntime.loadCharacter(definition(dict, extra), 'fixture_model', {}), true, 'actual character scene loads') end
local function step(thread)
    local ok, err = coroutine.resume(thread); eq(ok, true, 'controlled coroutine resumes: ' .. tostring(err)); return coroutine.status(thread)
end
local function finish(thread)
    local n = 0; while coroutine.status(thread) ~= 'dead' do n = n + 1; assert(n <= 30, 'probe must remain bounded'); step(thread) end
end

local thread, old, first, second

H.test('shared names and successful FX release after consumer cleanup', function()
    fresh()
    show('shared_idle', { { id = 'actor', type = 'ped', model = 'fixture_actor', offset = vector4(1, 0, 0, 0),
        animation = { dict = 'shared_idle', name = 'fixture_anim' } } })
    eq(count('request-anim', 'shared_idle'), 1, 'actual kora_lib loader requests a shared scene dictionary once')
    eq(count('play-anim', 'shared_idle'), 2, 'both owned scene peds consume the shared dictionary')
    SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'timeline_anim', name = 'fixture_anim' })
    eq(count('request-anim', 'timeline_anim'), 1, 'timeline cue acquires a second dictionary')
    SceneRuntime.playCue({ type = 'particle', target = 'character', asset = 'scene_ptfx', effect = 'fixture_fx' })
    eq(count('request-ptfx', 'scene_ptfx'), 1, 'particle cue requests named asset')
    eq(count('remove-anim'), 0, 'successful no-callback stream helper retains dictionary during use')
    eq(count('remove-ptfx'), 0, 'particle asset stays retained while FX consumer is live')
    SceneRuntime.cleanupScene()
    eq(count('remove-anim', 'shared_idle'), 1, 'cleanup releases acquired shared dictionary once')
    eq(count('remove-anim', 'timeline_anim'), 1, 'cleanup releases acquired timeline dictionary')
    eq(count('remove-ptfx', 'scene_ptfx'), 1, 'cleanup releases acquired FX asset')
    eq(count('stop-fx'), 1, 'cleanup stops particle consumer')
    eq(count('delete-entity'), 2, 'cleanup deletes both owned ped consumers')
    do
        local released, lastConsumer = math.huge, 0
        for i, call in ipairs(world.calls) do
            if call.kind == 'remove-anim' or call.kind == 'remove-ptfx' then released = math.min(released, i) end
            if call.kind == 'delete-entity' or call.kind == 'stop-fx' then lastConsumer = i end
        end
        eq(released > lastConsumer, true, 'asset release occurs after owned consumers stop')
    end
    SceneRuntime.cleanupScene()
    eq(count('remove-anim', 'shared_idle'), 1, 'repeated cleanup does not double-release dictionary')
    eq(count('remove-ptfx', 'scene_ptfx'), 1, 'repeated cleanup does not double-release FX asset')
end)

H.test('preloaded animation remains borrowed', function()
    fresh(); world.anim.borrowed_dict = true; show('borrowed_dict'); SceneRuntime.endMode()
    eq(count('request-anim', 'borrowed_dict'), 0, 'already-loaded external dictionary is borrowed without acquisition')
    eq(count('remove-anim', 'borrowed_dict'), 0, 'cleanup does not release the borrowed dictionary')
end)

H.test('invalid animation has no request ownership', function()
    fresh(); show('invalid_dict'); SceneRuntime.cleanupScene()
    eq(count('request-anim', 'invalid_dict'), 0, 'invalid dictionary fails before acquisition in actual stream helper')
    eq(count('remove-anim', 'invalid_dict'), 0, 'invalid dictionary has no owned request to release')
end)

H.test('animation timeout is already released by kora_lib', function()
    fresh(); world.heldAnim.timeout_dict = true
    thread = coroutine.create(function() show('timeout_dict') end); finish(thread)
    eq(count('request-anim', 'timeout_dict'), 1, 'animation timeout had one actual request')
    eq(count('remove-anim', 'timeout_dict'), 1, 'actual kora_lib helper already releases a timed-out dictionary')
    SceneRuntime.cleanupScene()
    eq(count('remove-anim', 'timeout_dict'), 1, 'scene must not duplicate helper timeout release')
end)

H.test('particle timeout is released by kora_lib', function()
    fresh(); show(); world.heldPtfx.timeout_fx = true
    thread = coroutine.create(function() SceneRuntime.playCue({ type = 'particle', asset = 'timeout_fx', effect = 'fixture_fx' }) end); finish(thread)
    eq(count('request-ptfx', 'timeout_fx'), 1, 'particle timeout requests named asset')
    eq(count('start-fx'), 0, 'timed-out asset creates no particle consumer')
    SceneRuntime.cleanupScene()
    eq(count('remove-ptfx', 'timeout_fx'), 1, 'failed direct particle request is released once')
end)

H.test('unused particle acquisition is cleaned', function()
    fresh(); show()
    SceneRuntime.playCue({ type = 'particle', target = 'missing', asset = 'unused_fx', effect = 'fixture_fx' })
    eq(count('start-fx'), 0, 'missing target produces no FX handle')
    SceneRuntime.cleanupScene()
    eq(count('remove-ptfx', 'unused_fx'), 1, 'unused requested asset is released on cleanup')
end)

H.test('successful stale animation is released', function()
    fresh(); show(); world.heldAnim.late_dict = true
    thread = coroutine.create(function() SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'late_dict', name = 'fixture_anim' }) end)
    eq(step(thread), 'suspended', 'actual stream call yields while scene dictionary loads')
    SceneRuntime.cleanupScene(); world.anim.late_dict = true; finish(thread)
    eq(count('play-anim', 'late_dict'), 0, 'stale cue does not animate deleted character')
    eq(count('remove-anim', 'late_dict'), 1, 'interrupted load cannot leave a successful late acquisition retained')
end)

H.test('new scene retains ownership through old completion', function()
    fresh(); show(); world.heldAnim.overlap_dict = true
    old = coroutine.create(function() SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'overlap_dict', name = 'fixture_anim' }) end)
    eq(step(old), 'suspended', 'older scene has pending dictionary')
    SceneRuntime.cleanupScene()
    local newer = coroutine.create(function() show('overlap_dict') end)
    eq(step(newer), 'suspended', 'newer scene requests same pending name')
    world.anim.overlap_dict = true; finish(newer)
    eq(count('play-anim', 'overlap_dict'), 1, 'newer live character starts its dictionary consumer')
    local beforeOld = count('remove-anim', 'overlap_dict'); finish(old)
    eq(count('remove-anim', 'overlap_dict'), beforeOld, 'late old completion does not release newer live dictionary use')
    SceneRuntime.cleanupScene()
    eq(count('remove-anim', 'overlap_dict') > beforeOld, true, 'newer scene releases its own dictionary on cleanup')
end)

H.test('stale animation timeout has no caller duplicate', function()
    fresh(); show(); world.heldAnim.abandoned_timeout = true
    thread = coroutine.create(function() SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'abandoned_timeout', name = 'fixture_anim' }) end)
    eq(step(thread), 'suspended', 'abandoned timeout begins inside the actual bounded helper')
    SceneRuntime.cleanupScene(); finish(thread)
    eq(count('remove-anim', 'abandoned_timeout'), 1, 'late failed helper owns its one timeout release without caller duplicate')
    SceneRuntime.cleanupScene()
    eq(count('remove-anim', 'abandoned_timeout'), 1, 'repeated cleanup after timeout adds no release')
end)

H.test('same-scene pending calls defer final release', function()
    fresh(); show(); world.heldAnim.two_pending = true
    first = coroutine.create(function() SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'two_pending', name = 'fixture_anim' }) end)
    second = coroutine.create(function() SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'two_pending', name = 'fixture_anim' }) end)
    eq(step(first), 'suspended', 'first same-scene request is pending')
    eq(step(second), 'suspended', 'second same-scene request is pending')
    SceneRuntime.cleanupScene(); world.anim.two_pending = true; finish(first)
    eq(count('remove-anim', 'two_pending'), 0, 'first late completion preserves second pending same-scene use')
    finish(second)
    eq(count('remove-anim', 'two_pending'), 1, 'last pending same-scene completion releases the name once')
    eq(count('play-anim', 'two_pending'), 0, 'late completions have no live old ped consumer')
end)

H.test('new borrower receives old acquisition ownership', function()
    fresh(); show(); world.heldAnim.borrowed_handoff = true
    old = coroutine.create(function() SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'borrowed_handoff', name = 'fixture_anim' }) end)
    eq(step(old), 'suspended', 'old scene owns a pending name for handoff')
    SceneRuntime.cleanupScene(); world.anim.borrowed_handoff = true; show('borrowed_handoff')
    eq(count('request-anim', 'borrowed_handoff'), 1, 'new scene borrows the already-ready old request without another acquisition')
    finish(old)
    eq(count('remove-anim', 'borrowed_handoff'), 0, 'old successful completion hands off without releasing the live new consumer')
    SceneRuntime.cleanupScene()
    eq(count('remove-anim', 'borrowed_handoff'), 1, 'new scene cleans the ownership handed off by the old request')
end)

H.test('preloaded particle remains borrowed', function()
    fresh(); show(); world.ptfx.borrowed_fx = true
    SceneRuntime.playCue({ type = 'particle', target = 'character', asset = 'borrowed_fx', effect = 'fixture_fx' })
    eq(count('request-ptfx', 'borrowed_fx'), 0, 'actual standard particle loader borrows a preloaded asset')
    SceneRuntime.cleanupScene()
    eq(count('remove-ptfx', 'borrowed_fx'), 0, 'preloaded particle asset is not released by borrowing scene')
end)

H.test('successful stale particle is released', function()
    fresh(); show(); world.heldPtfx.late_fx = true
    old = coroutine.create(function() SceneRuntime.playCue({ type = 'particle', target = 'character', asset = 'late_fx', effect = 'fixture_fx' }) end)
    eq(step(old), 'suspended', 'particle asset is pending before interrupted scene cleanup')
    SceneRuntime.cleanupScene(); world.ptfx.late_fx = true; finish(old)
    eq(count('start-fx'), 0, 'interrupted particle cue starts no stale consumer')
    eq(count('remove-ptfx', 'late_fx'), 1, 'successful stale particle acquisition is released once')
end)

H.test('own stop cleans pending animation without continuation', function()
    fresh(); show(); world.heldAnim.stopped_pending = true
    old = coroutine.create(function() SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'stopped_pending', name = 'fixture_anim' }) end)
    eq(step(old), 'suspended', 'own anim request is held in actual helper at resource stop')
    world.handlers.onClientResourceStop('unrelated_resource')
    eq(count('remove-anim', 'stopped_pending'), 0, 'foreign stop leaves pending own animation request alone')
    world.handlers.onClientResourceStop('kora_multichar')
    eq(count('remove-anim', 'stopped_pending'), 1, 'terminal own stop releases pending animation without resuming caller')
    do
        world.anim.stopped_pending = true; finish(old)
        eq(count('remove-anim', 'stopped_pending'), 1, 'late successful continuation cannot caller-release terminal acquisition again')
    end
end)

H.test('own stop cleans pending particle without continuation', function()
    fresh(); show(); world.heldPtfx.stopped_fx = true
    old = coroutine.create(function() SceneRuntime.playCue({ type = 'particle', target = 'character', asset = 'stopped_fx', effect = 'fixture_fx' }) end)
    eq(step(old), 'suspended', 'own particle request is held in actual helper at resource stop')
    world.handlers.onClientResourceStop('kora_multichar')
    eq(count('remove-ptfx', 'stopped_fx'), 1, 'terminal own stop releases pending particle without resuming caller')
end)

H.test('own stop retains and cleans retired pending requests', function()
    fresh(); show(); world.heldAnim.retired_pending = true
    old = coroutine.create(function() SceneRuntime.playCue({ type = 'animation', target = 'character', dict = 'retired_pending', name = 'fixture_anim' }) end)
    eq(step(old), 'suspended', 'retired scene still has a pending owned dictionary')
    SceneRuntime.cleanupScene()
    eq(count('remove-anim', 'retired_pending'), 0, 'normal cleanup leaves pending request to bounded completion')
    world.handlers.onClientResourceStop('kora_multichar')
    eq(count('remove-anim', 'retired_pending'), 1, 'terminal stop also releases a retired-scene pending request')
end)

H.test('foreign stop leaves owned assets and own stop disposes them', function()
    fresh(); show('stop_dict')
    world.handlers.onClientResourceStop('unrelated_resource')
    eq(count('remove-anim', 'stop_dict'), 0, 'foreign resource stop does not touch owned scene acquisitions')
    world.handlers.onClientResourceStop('kora_multichar')
    eq(count('remove-anim', 'stop_dict'), 1, 'own resource stop releases acquired dictionary')
end)

for _, replace in ipairs({ false, true }) do
    H.test(replace and 'retired timeline cannot reach replacement character' or 'retired timeline cannot request after cleanup', function()
        fresh(); world.heldAnim.retired_timeline = true
        local scene = definition()
        scene.timeline = { durationMs = 50, cues = {
            { type = 'animation', at = 0, target = 'character', dict = 'retired_timeline', name = 'fixture_anim' },
            { type = 'particle', at = 0, target = 'character', asset = 'after_retirement', effect = 'fixture_fx' },
        } }
        eq(SceneRuntime.loadCharacter(scene, 'fixture_model', {}), true, 'actual timeline scene loads')
        local timeline = assert(world.threads[1])
        eq(step(timeline), 'suspended', 'first due cue waits in actual streaming helper')
        local previousPed = world.nextEntity
        if replace then show() else SceneRuntime.cleanupScene() end
        eq(world.entities[previousPed], nil, 'former timeline character is disposed')
        if replace then eq(world.entities[world.nextEntity], true, 'replacement preview character is live') end
        local targets, nativeStart = {}, StartParticleFxLoopedOnEntity
        StartParticleFxLoopedOnEntity = function(effect, target, ...)
            targets[#targets + 1] = target
            return nativeStart(effect, target, ...)
        end
        world.anim.retired_timeline = true; finish(timeline)
        eq(count('play-anim', 'retired_timeline'), 0, 'retired animation does not run')
        eq(count('request-ptfx', 'after_retirement'), 0, 'retired due-cue loop requests no further asset')
        eq(count('start-fx'), 0, 'retired due-cue loop starts no FX on replacement')
        eq(#targets, 0, 'no native FX argument can name the new preview character')
    end)
end

print(('  %d controlled source/API assertions'):format(checks))
H.report('scene assets')
