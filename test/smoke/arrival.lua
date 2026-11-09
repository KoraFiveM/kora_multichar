-- The one-screen select's arrival: SceneRuntime.flyToArrival (lift / cruise /
-- descent in real script cameras) and SceneRuntime.completeArrival (place the
-- ped, effect, fade in, hand the camera back). Runs scene.lua against stubbed
-- natives with a fake clock that advances only when the code waits.
local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resource = arg[1] or scriptDir .. '../../'
local support = arg[2] or resource
package.path = support .. '/test/?.lua;' .. package.path
local H = require('harness')

local function vector(x, y, z, w)
    local result = { x = x, y = y, z = z }
    if w ~= nil then result.w = w end
    return result
end

local function noop() end

---Builds a fresh scene.lua environment. `q` records what the code did.
local function host(overrides)
    overrides = overrides or {}
    local e = {}
    for key, value in pairs(_G) do e[key] = value end
    local q = {
        log = {}, clock = 0, cams = {}, nextCam = 0, active = nil, interps = {},
        ped = { coords = nil }, alpha = {}, effects = {}, rendered = true,
        pedHandle = 1, ents = {},
        controlPressedAt = overrides.skipAt, ptfxLoads = {},
        render = overrides.render or vector(10.0, 20.0, 30.0),
    }
    local function log(entry) q.log[#q.log + 1] = entry end
    q.record = log

    e.vector3, e.vector4 = vector, vector
    e.Config = {
        sceneLimits = { streamTimeoutMs = 1, worldStreamTimeoutMs = 1 },
        spawnFlight = {
            liftHeight = 100.0, minAltitude = 150.0, maxAltitude = 400.0, liftDurationMs = 900,
            descentDurationMs = 1450, minTravelDurationMs = 1400, maxTravelDurationMs = 4200, unitsPerSecond = 650.0,
        },
    }
    e.Kora = {
        util = { isFiniteNumber = function(v) return type(v) == 'number' end },
        stream = {
            loadModel = function() return nil end,
            loadPtfx = function(asset)
                q.ptfxLoads[#q.ptfxLoads + 1] = asset
                if overrides.ptfxFails then return false end
                q.ptfxResident = q.ptfxResident or {}
                q.ptfxResident[asset] = true
                return true
            end,
        },
        cache = { playerId = function() return 1 end, onChange = noop, offChange = function(key) log('offChange:' .. key) end },
        callback = {},
    }
    e.GetCurrentResourceName = function() return 'kora_multichar' end
    e.AddEventHandler = noop
    q.threads = {}
    e.CreateThread = function(fn) q.threads[#q.threads + 1] = fn end
    e.PlayerPedId = function() return q.pedHandle end
    local function ent(handle)
        q.ents[handle] = q.ents[handle] or { visible = true, frozen = false, collision = true, alpha = 255 }
        return q.ents[handle]
    end
    q.ent = ent
    e.PlayerId = function() return 1 end
    e.GetGameTimer = function() return q.clock end
    e.Wait = function(ms) q.clock = q.clock + math.max(1, ms or 0) end
    e.SetTimeout = function(_, fn) q.timeout = fn end

    -- camera
    e.CreateCam = function()
        q.nextCam = q.nextCam + 1
        q.cams[q.nextCam] = { alive = true }
        return q.nextCam
    end
    e.DoesCamExist = function(id) return q.cams[id] ~= nil and q.cams[id].alive == true end
    e.DestroyCam = function(id) if q.cams[id] then q.cams[id].alive = false end end
    e.SetCamCoord = function(id, x, y, z) q.cams[id].coords = vector(x, y, z) end
    e.PointCamAtCoord = function(id, x, y, z) q.cams[id].lookAt = vector(x, y, z) end
    e.SetCamFov = function(id, fov) q.cams[id].fov = fov end
    e.GetCamFov = function() return 45.0 end
    e.GetCamCoord = function(id) return q.cams[id].coords end
    e.SetCamActive = function(id) q.active = id; log('active:' .. id) end
    e.SetCamActiveWithInterp = function(id, from, ms)
        assert(q.cams[id] and q.cams[id].alive, 'interp target must exist')
        assert(q.cams[from] and q.cams[from].alive, 'interp source must exist')
        q.active = id
        q.interps[#q.interps + 1] = { id = id, from = from, ms = ms, coords = q.cams[id].coords, lookAt = q.cams[id].lookAt }
        log('interp:' .. id)
    end
    e.RenderScriptCams = function(active, _, ms) q.rendered = active; log(('render:%s:%s'):format(tostring(active), tostring(ms))) end
    e.GetFinalRenderedCamCoord = function() return q.render end
    e.GetFinalRenderedCamRot = function() return vector(0.0, 0.0, 90.0) end
    e.GetFinalRenderedCamFov = function() return 40.0 end

    -- streaming / collision / traces
    e.IsNewLoadSceneActive = function() return false end
    e.NewLoadSceneStartSphere = function() return true end
    e.NewLoadSceneStop = noop
    e.IsNewLoadSceneLoaded = function() return true end
    e.RequestCollisionAtCoord = noop
    e.HasCollisionLoadedAroundEntity = function() return true end
    e.StartShapeTestCapsule = function() return 1 end
    e.GetShapeTestResult = function() return 2, false, nil end
    e.GetGroundZFor_3dCoord = function()
        if overrides.groundAt then return true, overrides.groundAt end
        return false, 0
    end

    -- ped
    e.SetEntityCoordsNoOffset = function(_, x, y, z) q.ped.coords = vector(x, y, z); log('park') end
    e.SetEntityCoords = function(_, x, y, z) q.ped.coords = vector(x, y, z); q.placedAt = q.clock; log('place') end
    e.SetEntityHeading = function(_, h) q.ped.heading = h end
    e.NetworkResurrectLocalPlayer = function() log('resurrect') end
    e.SetEntityAlpha = function(entity, a) q.alpha[#q.alpha + 1] = a; ent(entity).alpha = a end
    e.ResetEntityAlpha = function(entity) ent(entity).alpha = 255; log('resetAlpha') end
    e.SetEntityVisible = function(entity, visible) q.ped.visible = visible; ent(entity).visible = visible; log('visible:' .. tostring(visible)) end
    e.SetEntityCollision = function(entity, a) q.ped.collision = a; ent(entity).collision = a end
    e.FreezeEntityPosition = function(entity, frozen) q.ped.frozen = frozen; ent(entity).frozen = frozen end
    e.SetEntityInvincible = noop
    e.SetFocusEntity = noop
    e.ClearFocus = noop
    -- A player connects hidden and frozen; that is the state select begins in.
    e.IsEntityVisible = function() return not overrides.startHidden end
    e.GetPlayerInvincible = function() return false end
    e.IsEntityPositionFrozen = function() return overrides.startHidden == true end
    -- Before select the ped stood at 500,600,40. Once placed it is where it was
    -- placed, or on the ground below that if the test lets it fall.
    e.GetEntityCoords = function()
        if q.ped.coords and overrides.groundZ and q.placedAt and q.clock >= q.placedAt + (overrides.airFor or 0) then
            return vector(q.ped.coords.x, q.ped.coords.y, overrides.groundZ)
        end
        return q.ped.coords or vector(500.0, 600.0, 40.0)
    end
    e.IsEntityInAir = function()
        return overrides.airFor ~= nil and q.placedAt ~= nil and q.clock < q.placedAt + overrides.airFor
    end
    e.GetEntityHeading = function() return 12.0 end
    e.DoScreenFadeOut = noop
    e.DoScreenFadeIn = noop
    e.SetGameplayCamRelativeHeading = noop
    e.SetGameplayCamRelativePitch = noop

    -- environment
    e.ClearOverrideWeather = function() log('weather:clear') end
    e.ClearWeatherTypePersist = noop
    e.NetworkClearClockTimeOverride = noop
    e.ClearTimecycleModifier = noop
    e.NetworkOverrideClockTime = noop
    e.SetWeatherTypeNow = noop
    e.SetWeatherTypeNowPersist = noop
    e.SetTimecycleModifier = noop
    e.SetTimecycleModifierStrength = noop
    e.DeleteEntity = noop
    e.DoesEntityExist = function(entity) return entity ~= nil and entity ~= 0 end

    -- input
    e.IsDisabledControlJustPressed = function(_, control)
        if control ~= 22 then return false end
        return q.controlPressedAt ~= nil and q.clock >= q.controlPressedAt
    end

    -- ptfx
    e.HasNamedPtfxAssetLoaded = function(asset) return q.ptfxResident ~= nil and q.ptfxResident[asset] == true end
    e.UseParticleFxAssetNextCall = noop
    q.serverEvents = {}
    e.TriggerServerEvent = function(name, ...) q.serverEvents[#q.serverEvents + 1] = { name = name, args = { ... } }; log('server:' .. name) end
    e.StartParticleFxNonLoopedAtCoord = function(effect, x, y, z, _, _, _, scale)
        q.effects[#q.effects + 1] = { effect = effect, coords = vector(x, y, z), scale = scale }
        log('ptfx:' .. effect)
    end
    e.RemoveNamedPtfxAsset = function(asset)
        if q.ptfxResident then q.ptfxResident[asset] = nil end
        log('removePtfx:' .. asset)
    end

    assert(loadfile(support .. '/shared/scene.lua', 't', e))()
    assert(loadfile(resource .. '/scene.lua', 't', e))()
    return e, q
end

local DESTINATION = { id = 'legion', label = 'Legion Square', coords = vector(195.0, -934.0, 30.7, 144.0),
    preview = { camera = vector(219.0, -914.0, 45.0), lookAt = vector(195.0, -934.0, 30.7), fov = 40.0 } }

local function index(log, entry)
    for i, value in ipairs(log) do if value == entry then return i end end
    return nil
end

local function fly(overrides, location, opts)
    local e, q = host(overrides)
    local stages = {}
    local ok, reason = e.SceneRuntime.flyToArrival(location or DESTINATION, {
        skippable = opts == nil or opts.skippable ~= false,
        onStage = function(stage) stages[#stages + 1] = stage; q.record('stage:' .. stage) end,
    })
    return e, q, ok, reason, stages
end

------------------------------------------------------------------------------

H.test('the flight lifts, cruises and descends in that order, each in its own camera', function()
    local _, q, ok, reason, stages = fly()
    H.truthy(ok, 'the flight completes: ' .. tostring(reason))
    H.equal(table.concat(stages, ','), 'lift,cruise,descent', 'stage order reported to the UI')
    H.equal(#q.interps, 3, 'one camera blend per leg')
    H.equal(q.interps[1].ms, 900, 'lift duration comes from Config.spawnFlight')
    H.truthy(q.interps[2].ms >= 1400 and q.interps[2].ms <= 4200, 'cruise duration stays within the configured bounds')
    H.equal(q.interps[3].ms, 1450, 'descent duration comes from Config.spawnFlight')
    H.equal(q.interps[2].from, q.interps[1].id, 'cruise blends from the lift camera')
    H.equal(q.interps[3].from, q.interps[2].id, 'descent blends from the cruise camera')
end)

H.test('the lift starts exactly where the character-select camera is and rises above it', function()
    local _, q = fly()
    local handoff = q.cams[1]
    H.equal(handoff.coords.x, 10.0, 'handoff camera sits on the rendered camera (x)')
    H.equal(handoff.coords.z, 30.0, 'handoff camera sits on the rendered camera (z)')
    H.truthy(q.interps[1].coords.z > 30.0 + 100.0 - 0.001, 'the lift camera is well above the scene')
    H.equal(q.interps[1].coords.x, 10.0, 'the lift is straight up')
end)

H.test('the final shot is the authored arrival camera', function()
    local _, q = fly()
    H.equal(q.interps[3].coords.x, 219.0, 'descent ends on preview.camera')
    H.equal(q.interps[3].lookAt.x, 195.0, 'and looks at preview.lookAt')
    H.equal(q.cams[q.interps[3].id].fov, 40.0, 'with the authored field of view')
end)

H.test('a location with no authored shot gets a camera behind and above the ped', function()
    local plain = { id = 'house:1', label = 'Home', coords = vector(100.0, 200.0, 30.0, 0.0) }
    local _, q, ok = fly(nil, plain)
    H.truthy(ok, 'flight completes')
    local final = q.interps[3].coords
    H.truthy(final.y < 200.0, 'heading 0 faces north, so the camera sits south of the ped')
    H.close(final.z, 32.6, 0.01, 'and above them')
end)

H.test('the real weather and clock return before the descent, not after it', function()
    local _, q = fly()
    local clear = index(q.log, 'weather:clear')
    local descentBlend = index(q.log, 'interp:' .. q.interps[3].id)
    H.truthy(clear and descentBlend and clear < descentBlend,
        "the scene's weather override is cleared before the descent camera starts moving")
    H.truthy(index(q.log, 'stage:cruise') < clear, 'and not while the camera is still crossing the map')
end)

H.test('the streaming anchor moves to the destination only after the lift, so the scene stays loaded while rising', function()
    local _, q = fly()
    local lift, park, cruise = index(q.log, 'stage:lift'), index(q.log, 'park'), index(q.log, 'stage:cruise')
    H.truthy(lift and park and cruise, 'all three happen')
    H.truthy(lift < cruise and cruise < park, 'the ped is parked at the destination after the lift')
    H.equal(q.ped.coords.x, 195.0, 'and it is parked at the arrival point')
end)

H.test('Space shortens the camera travel but the destination is still streamed and the shot still lands', function()
    local _, q, ok, _, stages = fly({ skipAt = 100 })
    H.truthy(ok, 'a skipped flight still completes')
    H.equal(table.concat(stages, ','), 'lift,cruise,descent', 'every stage still runs')
    H.equal(q.interps[2].ms, 0, 'the cruise is cut to nothing')
    H.equal(q.interps[3].ms, 450, 'the descent becomes a short settle')
    H.truthy(index(q.log, 'park') ~= nil, 'the destination is still streamed')
end)

H.test('skipping is ignored when the config switches it off', function()
    local _, q, ok = fly({ skipAt = 0 }, nil, { skippable = false })
    H.truthy(ok, 'flight completes')
    H.equal(q.interps[1].ms, 900, 'lift keeps its full duration')
    H.equal(q.interps[3].ms, 1450, 'descent keeps its full duration')
end)

H.test('with no camera to start from the flight refuses without touching the ped or the world', function()
    local _, q, ok, reason = fly({ render = vector(0.0, 0.0, 0.0) })
    H.equal(ok, false, 'refused')
    H.truthy(type(reason) == 'string' and reason ~= '', 'with a reason the caller can log')
    H.falsy(index(q.log, 'park'), 'the ped is not moved')
    H.equal(#q.interps, 0, 'no camera blend started')
end)

H.test('a location without coordinates is refused', function()
    local _, _, ok = fly(nil, { id = 'broken', label = 'Broken' })
    H.equal(ok, false, 'refused')
end)

------------------------------------------------------------------------------

local ARRIVAL = { settleMs = 200, pedFadeMs = 600, handbackMs = 1000,
    ptfx = { enabled = true, asset = 'scr_rcbarry1', effect = 'scr_alien_teleport', scale = 1.5, zOffset = 0.25, releaseAfterMs = 4000 } }

local function arrive(overrides, config)
    local e, q = host(overrides)
    e.SceneRuntime.beginMode()
    H.truthy(e.SceneRuntime.flyToArrival(DESTINATION, { onStage = noop }), 'flight completes first')
    local config2 = config or ARRIVAL
    local copy = {}
    for key, value in pairs(config2) do copy[key] = value end
    copy.onPlaced = function()
        q.record('onPlaced')
        -- Applying a saved outfit can replace the player's ped outright.
        if overrides and overrides.swapPed then q.pedHandle = 2 end
    end
    e.SceneRuntime.completeArrival(DESTINATION.coords, copy)
    return e, q
end

H.test('the ped is placed hidden, login side effects run, and only then does the ped appear', function()
    local _, q = arrive()
    local place, placed, visible = index(q.log, 'place'), index(q.log, 'onPlaced'), index(q.log, 'visible:true')
    H.truthy(place and placed and visible, 'all three happen')
    H.truthy(place < placed and placed < visible, 'placement, then the loaded callback, then the reveal')
    H.equal(q.alpha[1], 0, 'the ped starts fully transparent')
    H.equal(q.ped.coords.x, 195.0, 'at the arrival point')
    H.equal(q.ped.heading, 144.0, 'facing the arrival heading')
end)

H.test('the effect plays at the ped\'s feet with the configured asset, effect, scale and offset', function()
    local _, q = arrive()
    H.equal(q.ptfxLoads[1], 'scr_rcbarry1', 'the asset is loaded first')
    H.equal(#q.effects, 1, 'one burst')
    H.equal(q.effects[1].effect, 'scr_alien_teleport', 'configured effect')
    H.equal(q.effects[1].scale, 1.5, 'configured scale')
    H.close(q.effects[1].coords.z, 30.7 - 1.0 + 0.25, 0.001, 'one metre below the root plus the offset')
    q.timeout()
    H.truthy(index(q.log, 'removePtfx:scr_rcbarry1'), 'the asset is released afterwards')
end)

H.test('the ped fades in over the configured time and ends fully opaque', function()
    local _, q = arrive()
    H.truthy(#q.alpha > 5, 'a ramp, not a pop')
    for i = 2, #q.alpha do H.truthy(q.alpha[i] >= q.alpha[i - 1], 'alpha only rises') end
    H.truthy(q.alpha[#q.alpha] <= 255, 'never above opaque')
    local reset = index(q.log, 'resetAlpha')
    H.truthy(reset, 'alpha is released at the end')
end)

H.test('the camera blends back to gameplay over the configured time before the mode ends', function()
    local _, q = arrive()
    local hand = index(q.log, 'render:false:1000')
    H.truthy(hand, 'RenderScriptCams(false, ..., handbackMs) is called with the configured time')
    local reveal, reset = index(q.log, 'visible:true'), index(q.log, 'resetAlpha')
    H.truthy(reveal < hand or hand < reset, 'the blend runs while the ped fades in')
    H.truthy(q.clock >= 1000, 'the arrival waits out the blend')
end)

H.test('the arrival leaves the ped where it was placed and does not drag it back to its pre-select position', function()
    local _, q = arrive()
    H.equal(q.ped.coords.x, 195.0, 'still at the arrival point after the mode ended')
    H.equal(q.ped.coords.y, -934.0, 'still at the arrival point (y)')
    H.equal(q.ped.frozen, false, 'and free to move again')
    H.equal(q.ped.visible, true, 'and visible')
end)

H.test('a player who connected hidden and frozen is visible, solid and free after arriving', function()
    local _, q = arrive({ startHidden = true })
    local ped = q.ent(q.pedHandle)
    H.equal(ped.visible, true, 'visible')
    H.equal(ped.frozen, false, 'not frozen')
    H.equal(ped.collision, true, 'solid')
    H.equal(ped.alpha, 255, 'fully opaque')
end)

H.test('the player still ends up visible, solid, free and opaque when the login replaces their ped', function()
    local _, q = arrive({ startHidden = true, swapPed = true })
    H.equal(q.pedHandle, 2, 'the ped really was replaced')
    local fresh = q.ent(2)
    H.equal(fresh.visible, true, 'the new ped is visible')
    H.equal(fresh.frozen, false, 'the new ped is not frozen')
    H.equal(fresh.collision, true, 'the new ped is solid')
    H.equal(fresh.alpha, 255, 'the new ped is fully opaque, not stuck at the fade-in start')
    H.equal(q.ped.coords.x, 195.0, 'still at the arrival point')
end)

H.test('the ped is placed lower by the configured offset', function()
    local config = { settleMs = 0, pedFadeMs = 100, handbackMs = 100, zOffset = -0.08, ptfx = { enabled = false } }
    local _, q = arrive(nil, config)
    H.close(q.ped.coords.z, 30.7 - 0.08, 0.0001, 'placed 0.08 below the arrival point')
    local _, none = arrive(nil, { settleMs = 0, pedFadeMs = 100, handbackMs = 100, ptfx = { enabled = false } })
    H.close(none.ped.coords.z, 30.7, 0.0001, 'no offset configured means the arrival point itself')
end)

H.test('the hidden ped is not frozen, so it falls to the ground instead of hovering at the coordinate', function()
    local e, q = host()
    e.SceneRuntime.beginMode()
    H.truthy(e.SceneRuntime.flyToArrival(DESTINATION, { onStage = noop }), 'flight completes')
    local frozenWhenPlaced
    e.SceneRuntime.completeArrival(DESTINATION.coords, {
        settleMs = 0, pedFadeMs = 100, handbackMs = 100, ptfx = { enabled = false },
        onPlaced = function() frozenWhenPlaced = q.ent(q.pedHandle).frozen end,
    })
    H.equal(frozenWhenPlaced, false, 'gravity applies while the ped is invisible')
end)

H.test('the ped is only revealed once it has reached the ground, and the effect plays where it landed', function()
    local _, q = arrive({ airFor = 700, groundZ = 29.7 })
    local landed = q.placedAt + 700
    H.truthy(q.clock >= landed, 'the arrival waited for the fall')
    H.close(q.effects[1].coords.z, 29.7 - 1.0 + 0.25, 0.001, 'the effect is at the ped\'s landed feet, not the placement height')
    local visible, place = index(q.log, 'visible:true'), index(q.log, 'place')
    H.truthy(place < visible, 'placed, then revealed')
end)

H.test('a ped that never lands cannot hang the arrival', function()
    local _, q = arrive({ airFor = 10 ^ 9 })
    H.equal(q.ent(q.pedHandle).visible, true, 'the player still arrives and is shown')
    H.truthy(q.clock < 60000, 'the wait is bounded')
end)

H.test('with the ground found the ped is placed at standing height, so there is nothing to wait for', function()
    local config = { settleMs = 0, pedFadeMs = 100, handbackMs = 100, zOffset = -0.08, ptfx = ARRIVAL.ptfx }
    local _, q = arrive({ groundAt = 29.7, airFor = 10 ^ 9 }, config)
    H.close(q.ped.coords.z, 29.7 + 1.0 - 0.08, 0.0001, 'placed a ped-height above the ground, less the offset')
    H.close(q.effects[1].coords.z, 29.7 + 0.25, 0.0001, 'the effect starts at the ground itself')
end)

H.test('the effect starts as soon as the ped is shown, without waiting for anything to load when it was preloaded', function()
    local e, q = host()
    e.SceneRuntime.preloadArrivalEffect(ARRIVAL.ptfx)
    H.equal(#q.threads, 1, 'the load runs off the flight, not inline')
    q.threads[1]()
    H.equal(#q.ptfxLoads, 1, 'asset requested once, before the flight')
    e.SceneRuntime.preloadArrivalEffect(ARRIVAL.ptfx)
    H.equal(#q.threads, 1, 'asking again does not start another load')

    e.SceneRuntime.beginMode()
    H.truthy(e.SceneRuntime.flyToArrival(DESTINATION, { onStage = noop }), 'flight completes')
    local copy = { onPlaced = noop }
    for key, value in pairs(ARRIVAL) do copy[key] = value end
    e.SceneRuntime.completeArrival(DESTINATION.coords, copy)
    H.equal(#q.ptfxLoads, 1, 'the arrival did not have to load it again')
    H.equal(#q.effects, 1, 'and the effect played')
end)

H.test('an asset that was not preloaded is still loaded at arrival, briefly, rather than skipped', function()
    local _, q = arrive()
    H.equal(#q.ptfxLoads, 1, 'loaded on demand')
    H.equal(#q.effects, 1, 'and played')
end)

H.test('releasing a preload that was never used gives the asset back', function()
    local e, q = host()
    e.SceneRuntime.preloadArrivalEffect(ARRIVAL.ptfx)
    q.threads[1]()
    e.SceneRuntime.releaseArrivalEffect()
    H.truthy(index(q.log, 'removePtfx:scr_rcbarry1'), 'asset released')
    e.SceneRuntime.releaseArrivalEffect()
    local count = 0
    for _, entry in ipairs(q.log) do if entry == 'removePtfx:scr_rcbarry1' then count = count + 1 end end
    H.equal(count, 1, 'releasing twice releases once')
end)

H.test('the arrival asks the server to show the effect to nearby players, sending only where it played', function()
    local _, q = arrive()
    H.equal(#q.serverEvents, 1, 'one request')
    local request = q.serverEvents[1]
    H.equal(request.name, 'qbmultichar:server:arrivalEffect', 'the relay event')
    H.equal(#request.args, 3, 'position only, no asset, effect or scale for the server to trust')
    H.close(request.args[1], 195.0, 0.001, 'x where the effect played')
    H.close(request.args[3], q.effects[1].coords.z, 0.001, 'z where the effect played')
    H.truthy(index(q.log, 'ptfx:scr_alien_teleport') < index(q.log, 'server:qbmultichar:server:arrivalEffect'),
        'the player sees their own effect first; the request follows')
end)

H.test('with syncing switched off nothing is sent and the effect stays local', function()
    local local_ = {}
    for key, value in pairs(ARRIVAL.ptfx) do local_[key] = value end
    local_.synced = false
    local _, q = arrive(nil, { settleMs = 0, pedFadeMs = 100, handbackMs = 100, ptfx = local_ })
    H.equal(#q.effects, 1, 'the arriving player still sees it')
    H.equal(#q.serverEvents, 0, 'no relay request')
end)

H.test('no effect means no request either', function()
    local _, q = arrive(nil, { settleMs = 0, pedFadeMs = 100, handbackMs = 100, ptfx = { enabled = false, asset = 'a', effect = 'b' } })
    H.equal(#q.serverEvents, 0, 'nothing to share')
end)

H.test('a failed asset load sends no request', function()
    local _, q = arrive({ ptfxFails = true })
    H.equal(#q.serverEvents, 0, 'nothing was played, so nothing is shared')
end)

H.test('an effect relayed from another player is played locally at the position given', function()
    local e, q = host()
    H.truthy(e.SceneRuntime.playSyncedArrivalEffect('scr_rcbarry1', 'scr_alien_teleport', 1.5, 10.0, 20.0, 30.0), 'played')
    H.equal(#q.effects, 1, 'one effect')
    H.equal(q.effects[1].effect, 'scr_alien_teleport', 'the effect named by the server')
    H.equal(q.effects[1].scale, 1.5, 'its scale')
    H.equal(q.effects[1].coords.y, 20.0, 'at the given position')
    H.equal(#q.serverEvents, 0, 'a relayed effect is never relayed again')
end)

H.test('a relayed effect with bad input is dropped without loading anything', function()
    local e, q = host()
    local bad = {
        { 5, 'e', 1.0, 0, 0, 0 }, { 'a', 5, 1.0, 0, 0, 0 }, { '', 'e', 1.0, 0, 0, 0 }, { 'a', '', 1.0, 0, 0, 0 },
        { string.rep('x', 65), 'e', 1.0, 0, 0, 0 }, { 'a', string.rep('x', 65), 1.0, 0, 0, 0 },
        { 'a', 'e', 1.0, 'x', 0, 0 }, { 'a', 'e', 1.0, 0, 0 / 0, 0 }, { 'a', 'e', 1.0, 0, 0, math.huge }, { 'a', 'e', 1.0, nil, 0, 0 },
    }
    for index_, args in ipairs(bad) do
        H.equal(e.SceneRuntime.playSyncedArrivalEffect(table.unpack(args, 1, 6)), false, ('bad input %d is refused'):format(index_))
    end
    H.equal(#q.ptfxLoads, 0, 'nothing was loaded for any of them')
    H.equal(#q.effects, 0, 'and nothing played')
    H.truthy(e.SceneRuntime.playSyncedArrivalEffect('a', 'e', 9999, 0.0, 0.0, 0.0), 'an absurd scale is clamped, not trusted')
    H.equal(q.effects[1].scale, 10.0, 'to the ceiling')
    H.truthy(e.SceneRuntime.playSyncedArrivalEffect('a', 'e', 'huge', 0.0, 0.0, 0.0), 'a non-numeric scale falls back to 1')
    H.equal(q.effects[2].scale, 1.0, 'to normal size')
end)

H.test('overlapping effects only give the asset back when the last one is done', function()
    local e, q = host()
    local timers = {}
    e.SetTimeout = function(_, fn) timers[#timers + 1] = fn end
    e.SceneRuntime.playSyncedArrivalEffect('scr_rcbarry1', 'a', 1.0, 0, 0, 0)
    e.SceneRuntime.playSyncedArrivalEffect('scr_rcbarry1', 'b', 1.0, 0, 0, 0)
    timers[1]()
    H.falsy(index(q.log, 'removePtfx:scr_rcbarry1'), 'one effect still running, so the asset stays')
    timers[2]()
    H.truthy(index(q.log, 'removePtfx:scr_rcbarry1'), 'released once both are done')
end)

H.test('an effect that is switched off or cannot be loaded never blocks the arrival', function()
    local _, q = arrive(nil, { settleMs = 0, pedFadeMs = 100, handbackMs = 100, ptfx = { enabled = false, asset = 'a', effect = 'b' } })
    H.equal(#q.effects, 0, 'disabled means no effect')
    local _, failing = arrive({ ptfxFails = true })
    H.equal(#failing.effects, 0, 'a failed asset load means no effect')
    H.equal(failing.ped.visible, true, 'but the ped still arrives')
end)

H.test('endMode without options still returns the ped to where it stood before character select', function()
    local e, q = host()
    e.SceneRuntime.beginMode()
    e.SceneRuntime.endMode()
    H.equal(q.ped.coords.x, 500.0, 'the original behaviour is intact for every other caller')
    H.equal(q.ped.coords.z, 40.0, 'including the height')
end)

H.report('arrival')
