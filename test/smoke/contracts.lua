local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local root = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')

local function read(path)
    local file = assert(io.open(root .. path, 'rb'))
    local body = file:read('*a')
    file:close()
    return body
end

local server, runtime, client, spawn, creator = read('server.lua'), read('scene.lua'), read('client.lua'), read('spawn.lua'), read('creator.lua')

H.test('server owns private buckets and the replicated cinematic mode', function()
    H.truthy(server:find("Player(src).state:set('qbmultichar:mode'", 1, true), 'server must publish qbmultichar:mode')
    H.truthy(server:find("mode == 'creator' and Config.buckets.creatorBase or Config.buckets.selectionBase", 1, true), 'mode must select configured bucket base')
    H.truthy(server:find("exports['qb-core']:SetPlayerBucket", 1, true), 'bucket changes should use qbcore compatibility')
    H.truthy(server:find('session.previousBucket', 1, true), 'cleanup must restore the original bucket')
end)

H.test('preview entities stay local and cleanup covers cinematic state', function()
    H.truthy(runtime:find('CreatePed(4, hash, coords.x, coords.y, coords.z, coords.w, false, false)', 1, true), 'scene peds must be non-networked')
    H.truthy(runtime:find('CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w, false, false)', 1, true), 'scene vehicles must be non-networked')
    for _, needle in ipairs({ 'DeleteEntity(entity)', 'DestroyCam(cam, false)', 'StopParticleFxLooped', 'StopSound(sound)', 'ClearFocus()', 'ClearOverrideWeather()', 'NetworkClearClockTimeOverride()', 'ClearTimecycleModifier()' }) do
        H.truthy(runtime:find(needle, 1, true), 'cleanup contract missing ' .. needle)
    end
    H.truthy(runtime:find('Config.sceneLimits.streamTimeoutMs', 1, true), 'asset and world streaming must be bounded')
    H.truthy(runtime:find('RequestCollisionAtCoord(ticket.coords.x, ticket.coords.y, ticket.coords.z)', 1, true), 'background spawn streaming must keep collision requested')
    H.truthy(runtime:find('StartShapeTestCapsule', 1, true), 'camera paths should use obstruction-aware collision checks')
    H.truthy(runtime:find('CAMERA_FAN_ANGLES', 1, true), 'blocked cameras should try nearby safe compositions')
    H.truthy(runtime:find('GetGroundZFor_3dCoord', 1, true), 'land characters should resolve against streamed ground collision')
    H.truthy(runtime:find('GetWaterHeight', 1, true), 'water vehicles should resolve against the water surface')
    H.truthy(runtime:find('SetPedIntoVehicle', 1, true), 'scene riders should be seated locally in their authored vehicles')
    H.truthy(runtime:find('TaskVehicleDriveToCoordLongrange', 1, true), 'authored local road drivers should be able to follow scene routes')
    H.truthy(runtime:find('TaskBoatMission', 1, true), 'authored local watercraft drivers should use boat navigation')
    H.truthy(runtime:find('DoScreenFadeOut', 1, true) and runtime:find('DoScreenFadeIn', 1, true), 'world streaming should remain behind a native blackout')
    H.truthy(runtime:find("state.cameras.spawnLift", 1, true), 'spawn travel should begin with a vertical lift camera')
    H.truthy(runtime:find("state.cameras.spawnTravel", 1, true), 'spawn travel should use an aerial cruise camera')
    H.truthy(runtime:find("state.cameras.spawnNext", 1, true), 'spawn travel should descend into a separate destination camera')
    H.truthy(runtime:find('SetCamActiveWithInterp(finalCam, travelCam', 1, true), 'spawn travel should fly down into the authored final shot')
end)

H.test('selection previews are cancellable and login only follows explicit continue', function()
    H.truthy(client:find('previewGeneration = previewGeneration + 1', 1, true), 'preview requests need generations')
    H.truthy(client:find('generation ~= previewGeneration', 1, true), 'stale previews must be discarded')
    H.truthy(client:find("RegisterNUICallback('multichar:select'", 1, true), 'continue callback must be explicit')
    H.truthy(client:find("TriggerServerEvent('qb-multicharacter:server:loadUserData'", 1, true), 'only select callback loads a character')
end)

H.test('spawn exit is mandatory and every success uses the central finalizer', function()
    H.truthy(spawn:find("RegisterNUICallback('multichar:spawn:exit'", 1, true), 'spawn escape callback exists')
    H.truthy(spawn:find('mandatory = true', 1, true), 'spawn escape must refuse cancellation')
    H.truthy(spawn:find('MulticharFinishSpawn(location.coords)', 1, true), 'all location types use central cleanup')
    H.truthy(spawn:find('function MulticharOpenNewSpawn()', 1, true), 'new characters must enter the mandatory spawn carousel too')
    H.truthy(client:find('SceneRuntime.endMode()', 1, true) and client:find('leaveServerMode()', 1, true), 'central finalizer clears client and server modes')
end)

H.test('scene studio exports through clipboard without writing server files', function()
    H.truthy(creator:find('QB.nui.copyToClipboard(text)', 1, true), 'studio should copy generated Lua')
    H.truthy(creator:find('definition.id = nil', 1, true), 'only the registry-level id should be omitted')
    H.truthy(creator:find("id = 'close'", 1, true) and creator:find("id = 'focal'", 1, true) and creator:find("id = 'establishing'", 1, true), 'new studio scenes should use the complete camera arc')
    H.falsy(creator:find('io.open', 1, true), 'studio must not write files')
end)

H.report('contracts')
