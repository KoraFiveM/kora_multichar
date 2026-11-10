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
    H.truthy(server:find("Player(src).state:set('kora_multichar:mode'", 1, true), 'server must publish kora_multichar:mode')
    H.truthy(server:find("mode == 'creator' and Config.buckets.creatorBase or Config.buckets.selectionBase", 1, true), 'mode must select configured bucket base')
    H.truthy(server:find("exports.kora_core:setPlayerBucket", 1, true), 'bucket changes should use kora_core compatibility')
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
    H.truthy(runtime:find("Kora.cache.onChange('ped'", 1, true) and runtime:find('newPed ~= state.hiddenPed', 1, true),
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
        "the hand-rolled rank table over kora_core's getPermission is gone")
    H.falsy(server:find('local ranks = {', 1, true), 'rank ordering belongs to kora_lib')
    H.truthy(server:find('Config.logout.minimumPermission', 1, true), 'the logout level must stay configurable')
    H.truthy(server:find('exports.kora_core:logout(src)', 1, true), 'the character drop belongs to kora_core')
    H.falsy(server:find("TriggerClientEvent('qb-multicharacter:client:chooseChar'", 1, true),
        'logout must not push character select; the client follows kora_core:loggedIn')
    H.truthy(client:find("AddStateBagChangeHandler('kora_core:loggedIn'", 1, true),
        'the client returns to selection by following the replicated login state')
    H.truthy(client:find("Kora.cache.onChange('serverId', try)", 1, true)
        and client:find('if done or not serverId or serverId == -1 then return end', 1, true),
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
    H.truthy(spawn:find('multicharFinishSpawn(location.coords, lastIsNew)', 1, true), 'all location types use central cleanup, keeping a new character new')
    H.falsy(spawn:find('function MulticharOpenNewSpawn()', 1, true), 'new characters must not open the spawn carousel')
    H.truthy(client:find('finishAt(Config.defaultSpawn)', 1, true), 'new characters must spawn at the configured first-arrival point')
    H.truthy(client:find('exports.kora_clothing:applyStarterAppearance()', 1, true) and client:find('if isNew then resetNewCharacterAppearance() end', 1, true), 'new characters are dressed in the starter outfit before the ped is read and moved')
    H.truthy(client:find('SceneRuntime.endMode()', 1, true) and client:find('leaveServerMode()', 1, true), 'central finalizer clears client and server modes')
end)

H.test('spawn completion is announced as an event, after the fade-in', function()
    H.truthy(client:find("TriggerEvent('kora_multichar:client:spawnComplete'", 1, true), 'the finalizer must announce spawn completion')
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

H.test('scene studio adds by model and moves through kora_lib placement', function()
    H.truthy(creator:find('IsModelInCdimage(hash)', 1, true) and creator:find('local function addEntity(payload)', 1, true), 'a model is checked before an entity is added')
    H.truthy(creator:find('nextEntityId(kind)', 1, true), 'ids are generated, not typed')
    H.falsy(creator:find("('entity_%d')", 1, true), 'the panel no longer supplies entity ids')
    H.truthy(creator:find('Kora.placement.start(entity.model', 1, true), 'Move uses kora_lib placement')
    H.truthy(creator:find('copy = false', 1, true), 'placement must not write the clipboard')
    H.truthy(creator:find('SetNuiFocus(creator.cursor, creator.cursor)', 1, true), 'studio focus is restored after placement')
    H.truthy(creator:find('creator.placing or type(data)', 1, true), 'panel actions are ignored while placing')
    H.truthy(creator:find('library = Config.creator.library', 1, true), 'the picker library is sent to the panel')
    local env = setmetatable({ vector3 = function(x, y, z) return { x = x, y = y, z = z } end, vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }, { __index = _G })
    assert(loadfile(root .. 'config.lua', 't', env))()
    local Config = env.Config
    H.truthy(type(Config.creator.library) == 'table' and #Config.creator.library.ped > 0 and #Config.creator.library.vehicle > 0 and #Config.creator.library.prop > 0, 'library covers peds, vehicles and props')
    for kind, rows in pairs(Config.creator.library) do
        for _, row in ipairs(rows) do
            H.truthy(type(row[1]) == 'string' and row[1]:match('^[%w_%-]+$') and type(row[2]) == 'string', ('library %s row must be { model, label }'):format(kind))
        end
    end
end)

H.report('contracts')
