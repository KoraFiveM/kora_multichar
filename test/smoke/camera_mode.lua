-- Config.cameraMode: 'focus' keeps the camera on the previewed ped, 'cycle'
-- keeps the looping timeline camera cuts. Reuses the preview_lifecycle host so
-- the real scene.lua runs against inert natives; no rendering claims.
local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resource = arg[1] or scriptDir .. '../../'
local support = arg[2] or resource
package.path = support .. '/test/?.lua;' .. package.path
local H = require('harness')
local equal = H.equal

local file = assert(io.open(scriptDir .. 'preview_lifecycle.lua', 'r'))
local source = file:read('a'); file:close()
local head = assert(source:match('^(.-)local function run%(co%)'), 'host marker missing')
local chunk = assert(load(head .. '\nreturn host, scene, vector', '@preview_lifecycle_host', 't', setmetatable({ arg = { resource, support } }, { __index = _G })))
local host, scene, vector = chunk()

local function timelineScene(id, x)
    local value = scene(id, x)
    value.cameras[2] = { id = 'focal', offset = vector(5, 5, 3), lookAt = vector(0, 0, 1), fov = 40 }
    value.timeline = { durationMs = 100, loop = true, cues = {
        { at = 0, type = 'camera', camera = 'close' },
        { at = 0, type = 'entityVisibility', target = 'character', visible = false },
        { at = 0, type = 'camera', camera = 'focal', transitionMs = 500 },
    } }
    return value
end

local function load(mode, id)
    local e, q = host()
    e.Config.cameraMode = mode
    local interps, visibility = 0, 0
    local plain = e.SetCamActiveWithInterp
    e.SetCamActiveWithInterp = function(...) interps = interps + 1; return plain(...) end
    e.SetEntityVisible = function() visibility = visibility + 1 end
    local before = #q.threads
    local co = coroutine.create(function() return e.SceneRuntime.loadCharacter(timelineScene(id or 'a'), 'saved', {}) end)
    local ok, result
    repeat ok, result = coroutine.resume(co); assert(ok, result) until coroutine.status(co) == 'dead'
    equal(result, true, 'preview loads')
    local loaded = visibility
    for index = before + 1, #q.threads do assert(coroutine.resume(q.threads[index])) end
    return e, q, function() return interps, visibility - loaded end
end

H.test('focus mode (default) never cuts to another camera angle', function()
    local _, q, counts = load('focus')
    local interps, visibility = counts()
    equal(interps, 0, 'no camera interpolation after the first shot')
    equal(visibility, 1, 'non-camera cues still play')
    equal(q.active, 1, 'the opening camera stays active')
end)

H.test('an unset cameraMode behaves as focus', function()
    local _, _, counts = load(nil)
    equal((counts()), 0, 'no camera cues without a configured mode')
end)

H.test('cycle mode keeps the timeline camera cuts', function()
    local _, q, counts = load('cycle')
    local interps, visibility = counts()
    equal(interps, 1, 'timeline moved to the focal camera')
    equal(visibility, 1, 'other cues still play')
    equal(q.active, 2, 'focal camera is active')
end)

H.test('selecting another ped still moves the camera in focus mode', function()
    local e, q = load('focus', 'a')
    local first = q.active
    local co = coroutine.create(function() return e.SceneRuntime.loadCharacter(timelineScene('b', 10), 'saved', {}) end)
    local ok, result
    repeat ok, result = coroutine.resume(co); assert(ok, result) until coroutine.status(co) == 'dead'
    equal(result, true, 'second preview loads')
    equal(q.active ~= first, true, 'camera moved to the new ped scene')
    e.SceneRuntime.endMode()
end)

H.report('camera_mode')
