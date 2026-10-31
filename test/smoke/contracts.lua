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
    H.truthy(server:find("exports.kora_core:setPlayerBucket", 1, true), 'bucket changes should use qbcore compatibility')
    H.truthy(server:find('session.previousBucket', 1, true), 'cleanup must restore the original bucket')
end)

H.test('preview entities stay local and cleanup covers cinematic state', function()
    H.truthy(runtime:find('CreatePed(4, hash, coords.x, coords.y, coords.z, coords.w, false, false)', 1, true), 'scene peds must be non-networked')
    H.truthy(runtime:find('CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w, false, false)', 1, true), 'scene vehicles must be non-networked')
    for _, needle in ipairs({ 'DeleteEntity(entity)', 'DestroyCam(cam, false)', 'StopParticleFxLooped', 'StopSound(sound)', 'ClearFocus()', 'ClearOverrideWeather()', 'NetworkClearClockTimeOverride()', 'ClearTimecycleModifier()' }) do
        H.truthy(runtime:find(needle, 1, true), 'cleanup contract missing ' .. needle)
    end
    H.truthy(runtime:find('Config.sceneLimits.streamTimeoutMs', 1, true), 'asset loads must be bounded')
    H.truthy(runtime:find('Config.sceneLimits.worldStreamTimeoutMs', 1, true),
        'world streaming needs its own budget, separate from the hard asset-load one')
    H.truthy(runtime:find('RequestCollisionAtCoord(ticket.coords.x, ticket.coords.y, ticket.coords.z)', 1, true), 'background spawn streaming must keep collision requested')
    -- A load scene is a streaming hint. On a cold client it often never
    -- reports itself loaded, and the engine refuses to start one at all while
    -- it is still finishing the join. Neither may cost the player their scene.
    H.truthy(runtime:find('STREAM_START_WINDOW_MS', 1, true),
        'a refused load scene must be retried, not read as a missing area')
    H.falsy(runtime:find("'scene area could not be streamed'", 1, true),
        'a slow world stream must degrade into a visible scene, never a failed character preview')
    H.truthy(runtime:find("if not streamWorld(scene.anchor, generation) then return false, 'stale preview' end", 1, true),
        'only a superseded preview may abort the character scene load')
    H.truthy(runtime:find('StartShapeTestCapsule', 1, true), 'camera paths should use obstruction-aware collision checks')
    H.truthy(runtime:find('CAMERA_FAN_ANGLES', 1, true), 'blocked cameras should try nearby safe compositions')
    H.truthy(runtime:find('GetGroundZFor_3dCoord', 1, true), 'land characters should resolve against streamed ground collision')
    H.truthy(runtime:find('GetWaterHeight', 1, true), 'water vehicles should resolve against the water surface')
    H.truthy(runtime:find('SetPedIntoVehicle', 1, true), 'scene riders should be seated locally in their authored vehicles')
    H.truthy(runtime:find('TaskVehicleDriveToCoordLongrange', 1, true), 'authored local road drivers should be able to follow scene routes')
    H.truthy(runtime:find('TaskBoatMission', 1, true), 'authored local watercraft drivers should use boat navigation')
    H.truthy(runtime:find('DoScreenFadeOut', 1, true) and runtime:find('DoScreenFadeIn', 1, true), 'world streaming should remain behind a native blackout')
    -- Finishing the game's own first spawn creates a NEW player ped, silently
    -- undoing beginMode's hide. That only ever happens on the first load of a
    -- session, which is why this arrived as "it works on the second load".
    H.truthy(runtime:find('if ped ~= state.hiddenPed then', 1, true),
        'the cinematic hide must be re-asserted when the engine swaps the player ped')
    H.truthy(client:find('local function awaitStablePlayerPed()', 1, true),
        'selection must wait for a real, settled player ped, not just a started session')
    H.truthy(runtime:find("state.cameras.spawnLift", 1, true), 'spawn travel should begin with a vertical lift camera')
    H.truthy(runtime:find("state.cameras.spawnTravel", 1, true), 'spawn travel should use an aerial cruise camera')
    H.truthy(runtime:find("state.cameras.spawnNext", 1, true), 'spawn travel should descend into a separate destination camera')
    H.truthy(runtime:find('SetCamActiveWithInterp(finalCam, travelCam', 1, true), 'spawn travel should fly down into the authored final shot')
end)

H.test('staff logout is permission-gated and travels on the replicated login state', function()
    H.truthy(server:find('Kora.permissions.hasLevel', 1, true), 'staff gating must go through kora_lib, not a local rank table')
    H.falsy(server:find('exports.kora_core:getPermission', 1, true),
        "the hand-rolled rank table over qbcore's getPermission is gone")
    H.falsy(server:find('local ranks = {', 1, true), 'rank ordering belongs to kora_lib')
    H.truthy(server:find('Config.logout.minimumPermission', 1, true), 'the logout level must stay configurable')
    H.truthy(server:find('exports.kora_core:logout(src)', 1, true), 'the character drop belongs to qbcore')
    H.falsy(server:find("TriggerClientEvent('qb-multicharacter:client:chooseChar'", 1, true),
        'logout must not push character select; the client follows qbcore:loggedIn')
    H.truthy(client:find("AddStateBagChangeHandler('qbcore:loggedIn'", 1, true),
        'the client returns to selection by following the replicated login state')
    H.truthy(client:find('while not serverId or serverId == -1 do', 1, true),
        'the login-state bag must wait for kora_lib to resolve its stable server id')
    H.truthy(client:find('if returningToSelection or currentMode ~= nil then return end', 1, true),
        'the return must not re-enter selection or fight an active cinematic mode')
end)

H.test('selection previews are cancellable and login only follows explicit continue', function()
    H.truthy(client:find('previewGeneration = previewGeneration + 1', 1, true), 'preview requests need generations')
    H.truthy(client:find('generation ~= previewGeneration', 1, true), 'stale previews must be discarded')
    H.truthy(client:find("RegisterNUICallback('multichar:select'", 1, true), 'continue callback must be explicit')
    H.truthy(client:find("TriggerServerEvent('qb-multicharacter:server:loadUserData'", 1, true), 'only select callback loads a character')
    H.falsy(client:find("send('multichar:input'", 1, true), 'focused NUI keyboard events should not be duplicated by a Lua input poll')
end)

H.test('spawn exit is mandatory and every success uses the central finalizer', function()
    H.truthy(spawn:find("RegisterNUICallback('multichar:spawn:exit'", 1, true), 'spawn escape callback exists')
    H.truthy(spawn:find('mandatory = true', 1, true), 'spawn escape must refuse cancellation')
    H.truthy(spawn:find('multicharFinishSpawn(location.coords)', 1, true), 'all location types use central cleanup')
    H.falsy(spawn:find('function MulticharOpenNewSpawn()', 1, true), 'new characters must not open the spawn carousel')
    H.truthy(client:find('finishAt(Config.defaultSpawn)', 1, true), 'new characters must spawn at the configured first-arrival point')
    H.truthy(client:find('SceneRuntime.endMode()', 1, true) and client:find('leaveServerMode()', 1, true), 'central finalizer clears client and server modes')
end)

-- The cleared `qbmultichar:mode` bag is NOT a usable "player has spawned"
-- signal: leaveServerMode runs before the teleport, and the clear replicates
-- asynchronously on top of that. Consumers that must wait for a real spawn
-- (kora_clothing's first-character fitting room) need an explicit event, fired
-- after the ped is placed and the fade-in has completed.
H.test('spawn completion is announced as an event, after the fade-in', function()
    H.truthy(client:find("TriggerEvent('qbmultichar:client:spawnComplete'", 1, true), 'the finalizer must announce spawn completion')
    H.truthy(client:find('while not IsScreenFadedIn() and GetGameTimer() < deadline do', 1, true),
        'the announcement must wait for the fade-in to actually complete, and be bounded')
    H.truthy(client:find('local isNew = pendingNewCharacter', 1, true),
        'the finalizer must consume the new-character flag so listeners can tell creation from login')
    H.truthy(client:find('pendingNewCharacter = true', 1, true), 'the new-character handoff must set that flag')
    H.truthy(client:find('announceSpawnComplete(isNew)', 1, true), 'every spawn finalization announces, new or returning')
end)

H.test('scene studio exports through clipboard without writing server files', function()
    H.truthy(creator:find('Kora.nui.copyToClipboard(text)', 1, true), 'studio should copy generated Lua')
    H.truthy(creator:find('definition.id = nil', 1, true), 'only the registry-level id should be omitted')
    H.truthy(creator:find("id = 'close'", 1, true) and creator:find("id = 'focal'", 1, true) and creator:find("id = 'establishing'", 1, true), 'new studio scenes should use the complete camera arc')
    H.falsy(creator:find('io.open', 1, true), 'studio must not write files')
    H.truthy(creator:find('Kora.freecam.start({', 1, true), 'the studio should use kora_lib freecam')
    H.truthy(creator:find('Kora.instructional.show({', 1, true), 'the studio should use kora_lib instructional buttons')
end)

H.report('contracts')
