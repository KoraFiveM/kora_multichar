-- Actual Lua runtime/caller scheduling with inert natives; no rendering claims.
local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resource = arg[1] or scriptDir .. '../../'
local support = arg[2] or resource
package.path = support .. '/test/?.lua;' .. package.path
local H = require('harness')
local equal = H.equal
local function noop() end
local function vector(x, y, z, w) return { x=x, y=y, z=z, w=w } end
local function scene(id, x)
    return {id=id,anchor=vector(x or 0,0,0,0),character={offset=vector(0,0,0,0)},entities={},
        cameras={{id='close',offset=vector(0,3,2),lookAt=vector(0,0,1),fov=38}},selectors={},timeline={cues={},durationMs=0}}
end
local function host(withClient)
    local e = {}; for key, value in pairs(_G) do e[key] = value end
    local q={created=0,active=nil,rendered=false,cameras={},traces={},threads={},events={},handlers={},nui={},loads={},failModels={},pauseTrace=false}
    e.vector3, e.vector4 = vector, vector
    e.Config={defaultScene='default',defaultSpawn=vector(25,0,0,0),sceneLimits={streamTimeoutMs=1,worldStreamTimeoutMs=1},
        spawnFlight={liftDurationMs=0,minTravelDurationMs=0,maxTravelDurationMs=0,descentDurationMs=0}}
    e.QB={util={isFiniteNumber=function(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end},
        stream={loadModel=function(model) return not q.failModels[model] and model or nil end},callback={},cache={}}
    e.exports={kora_core={claimUI=noop}}
    e.PlayerPedId=function() return 1 end
    e.GetCurrentResourceName=function() return 'kora_multichar' end
    e.GetGameTimer=function() return 0 end
    e.GetResourceState=function() return 'stopped' end
    e.IsScreenFadedOut=function() return true end
    e.IsScreenFadedIn=function() return true end
    e.IsNewLoadSceneActive=function() return false end
    e.NewLoadSceneStartSphere=function() return true end
    e.HasCollisionLoadedAroundEntity=function() return true end
    e.DoesEntityExist=function(value) return value~=nil and value~=0 end
    e.IsModelValid=function() return true end
    e.joaat=function(model) return model end
    e.GetGroundZFor_3dCoord=function() return false,0 end
    e.CreatePed=function() return 100 end
    e.GetEntityCoords=function() return vector(0,0,0) end
    e.GetEntityHeading=function() return 0 end
    e.IsEntityVisible=function() return true end
    e.GetPlayerInvincible=function() return false end
    e.PlayerId=function() return 1 end
    e.IsEntityPositionFrozen=function() return false end
    e.CreateCam=function()
        q.created=q.created+1
        if q.failCreateAt==q.created then return 0 end
        q.cameras[q.created]={alive=true}; return q.created
    end
    e.DoesCamExist=function(id) return q.cameras[id] and q.cameras[id].alive==true or false end
    e.DestroyCam=function(id) if q.cameras[id] then q.cameras[id].alive=false end end
    e.SetCamCoord=function(id,x,y,z) q.cameras[id].coords=vector(x,y,z) end
    e.GetCamCoord=function(id) return q.cameras[id].coords end
    e.GetFinalRenderedCamCoord=function() return q.active and q.cameras[q.active].coords or vector(0,0,0) end
    e.GetCamFov=function() return 45 end
    e.SetCamActive=function(id) q.active=id end
    e.SetCamActiveWithInterp=function(id,from)
        equal(e.DoesCamExist(id),true,'interpolation target exists')
        equal(e.DoesCamExist(from),true,'interpolation source survives replacement')
        q.active=id
    end
    e.RenderScriptCams=function(active) q.rendered=active end
    e.StartShapeTestCapsule=function()
        local id=#q.traces+1; q.traces[id]={pause=q.pauseTrace}; q.pauseTrace=false; return id
    end
    e.GetShapeTestResult=function(id)
        local trace=q.traces[id]
        if trace.pause and not trace.waited then trace.waited=true; return 1,false,nil end
        return 2,false,nil
    end
    e.Wait=function() coroutine.yield('trace') end
    e.CreateThread=function(fn) q.threads[#q.threads+1]=coroutine.create(fn) end
    e.AddEventHandler=function(name,fn)
        q.handlers[name]=q.handlers[name] or {}; table.insert(q.handlers[name],fn)
    end
    e.RegisterNetEvent=function(name,fn) q.events[name]=fn end
    e.RegisterNUICallback=function(name,fn) q.nui[name]=fn end
    e.SendNUIMessage=function(value) q.messages=q.messages or {}; table.insert(q.messages,value) end
    for _,name in ipairs({'RequestCollisionAtCoord','SetEntityCoordsNoOffset','FreezeEntityPosition','SetEntityCollision',
        'SetEntityVisible','SetFocusEntity','ClearFocus','ClearOverrideWeather','ClearWeatherTypePersist','NetworkClearClockTimeOverride',
        'ClearTimecycleModifier','DoScreenFadeIn','DoScreenFadeOut','SetEntityInvincible','PointCamAtCoord','SetCamFov',
        'SetEntityAsMissionEntity','SetBlockingOfNonTemporaryEvents','SetModelAsNoLongerNeeded','DeleteEntity','SetEntityHeading',
        'ShutdownLoadingScreen','ShutdownLoadingScreenNui','SetNuiFocus','TriggerServerEvent','SetEntityCoords','NetworkResurrectLocalPlayer',
        'NetworkOverrideClockTime','SetWeatherTypeNow','SetWeatherTypeNowPersist','SetTimecycleModifier','SetTimecycleModifierStrength'}) do e[name]=noop end
    assert(loadfile(support..'/shared/scene.lua','t',e))()
    assert(loadfile(resource..'/scene.lua','t',e))()
    if withClient then
        q.catalog={default=scene('default'),preferred=scene('preferred',10)}
        q.catalog.preferred.selectors={{job='police'}}; q.catalog.preferred.priority=1
        q.characters={{citizenid='A',cid=1,charinfo={gender=0},job={name='police'}},
            {citizenid='B',cid=2,charinfo={gender=1},job={name='police'}}}
        e.QB.callback.trigger=function(name, citizenid)
            if name=='qbmultichar:server:enterMode' then
                if q.pauseEnter then q.pauseEnter=false; coroutine.yield('enter') end; return true
            end
            if name=='qbmultichar:server:leaveMode' then
                if q.pauseLeave then q.pauseLeave=false; coroutine.yield('leave') end; return true
            end
            if name=='qb-multicharacter:server:setupCharacters' then return q.characters end
            if name=='qb-multicharacter:server:GetNumberOfCharacters' then return 5 end
            if name=='qbmultichar:server:getScenes' then
                local result=q.catalog
                if q.pauseCatalog then q.pauseCatalog=false; coroutine.yield('catalog') end
                return result
            end
            if name=='qb-multicharacter:server:deleteCharacter' then
                for index,character in ipairs(q.characters) do
                    if character.citizenid==citizenid then table.remove(q.characters,index); break end
                end
                return true
            end
            if name=='qb-multicharacter:server:getSkin' then
                if q.pauseSkin then q.pauseSkin=false; coroutine.yield('skin') end
                return 'saved',{}
            end
            error('unexpected callback '..name)
        end
        local actual=e.SceneRuntime.loadCharacter
        e.SceneRuntime.loadCharacter=function(s,m,k)
            q.loads[#q.loads+1]={scene=s and s.id,model=m}; return actual(s,m,k)
        end
        assert(loadfile(resource..'/client.lua','t',e))()
        q.events['qb-multicharacter:client:chooseChar']()
    end
    return e,q
end
local function run(co)
    local values=table.pack(coroutine.resume(co)); assert(values[1],values[2]); return table.unpack(values,2,values.n)
end
local function pause(fn,q)
    q.pauseTrace=true; local co=coroutine.create(fn); equal(run(co),'trace','trace suspends'); equal(coroutine.status(co),'suspended'); return co
end
local function readyCount(q)
    local count=0; for _,m in ipairs(q.messages or {}) do if m.action=='multichar:previewReady' then count=count+1 end end; return count
end
local function focus(e,q,new)
    local before=#q.threads
    if new then q.nui['multichar:createPreview']({gender=0},noop) else q.nui['multichar:preview']({citizenid='A'},noop) end
    equal(#q.threads,before+1,'one preview task'); return q.threads[#q.threads]
end
-- Each case suspends actual traceCameraPath after the first pending result.
for _,kind in ipairs({'character','static','flight'}) do
    for _,cancel in ipairs({'endMode','cleanupScene','replacement'}) do
        H.test(kind .. ' preview retires on ' .. cancel, function()
            local e,q=host()
            if kind=='flight' then equal(e.SceneRuntime.previewSpawn({coords=vector(0,0,0)}),true) end
            local operation=kind=='character' and function() return e.SceneRuntime.loadCharacter(scene('old'),'saved',{}) end
                or function() return e.SceneRuntime.previewSpawn({coords=vector(50,0,0)}) end
            local co=pause(operation,q)
            if cancel=='replacement' then equal(e.SceneRuntime.loadCharacter(scene('new',100),'saved',{}),true)
            else e.SceneRuntime[cancel]() end
            local cameras,active,rendered=q.created,q.active,q.rendered
            local loaded,second,third=run(co)
            equal(q.created,cameras,'retired preview creates no camera')
            equal(q.active,active,'retired preview does not activate a camera')
            equal(q.rendered,rendered,'retired preview leaves rendering ownership unchanged')
            equal(loaded,false)
            equal(kind=='character' and second or third,kind=='character' and 'stale preview' or e.SceneRuntime.PREVIEW_SUPERSEDED)
        end)
    end
end
-- Every saved-character fallback attempt may itself yield in a camera trace.
for attempt=1,3 do
    for _,cancel in ipairs({'close','finish','cleanup','newfocus','resourceStop'}) do
        H.test('saved preview attempt ' .. attempt .. ' retires on ' .. cancel, function()
            local e,q=host(true)
            if attempt==2 then q.catalog.preferred.cameras={} end
            if attempt==3 then q.failModels.saved=true end
            q.pauseTrace=true; local co=focus(e,q)
            equal(run(co),'trace'); equal(#q.loads,attempt)
            if cancel=='close' then q.events['qb-multicharacter:client:closeNUI']()
            elseif cancel=='finish' then e.multicharFinishSpawn(vector(50,0,0))
            elseif cancel=='cleanup' then e.SceneRuntime.cleanupScene()
            elseif cancel=='newfocus' then q.failModels.saved=nil; run(focus(e,q))
            else for _,fn in ipairs(q.handlers.onClientResourceStop) do fn('kora_multichar') end end
            local cameras,loads,ready,active=q.created,#q.loads,readyCount(q),q.active
            run(co)
            equal(q.created,cameras,'cancelled caller creates no camera')
            equal(#q.loads,loads,'cancelled caller starts no fallback')
            equal(readyCount(q),ready,'cancelled caller sends no ready result')
            equal(q.active,active,'replacement camera preserved')
        end)
    end
end
for _,cancel in ipairs({'close','cleanup','newfocus'}) do
    H.test('new-character preview retires on ' .. cancel, function()
        local e,q=host(true); q.pauseTrace=true; local co=focus(e,q,true); equal(run(co),'trace')
        if cancel=='close' then q.events['qb-multicharacter:client:closeNUI']()
        elseif cancel=='cleanup' then e.SceneRuntime.cleanupScene()
        else run(focus(e,q,true)) end
        local created,ready=q.created,readyCount(q); run(co)
        equal(q.created,created,'retired new preview creates no camera')
        equal(readyCount(q),ready,'retired new preview stays silent')
    end)
end
-- These await phases precede SceneRuntime generation capture entirely.
for _,phase in ipairs({'skin','catalog','newcatalog'}) do
    for _,cancel in ipairs({'close','finish','spawn','reentry','delete'}) do
        H.test(phase .. ' await retires on ' .. cancel, function()
            local e,q=host(true)
            if phase=='skin' then q.pauseSkin=true
            else
                for key in pairs(q.catalog) do q.catalog[key]=nil end
                q.catalog={default=scene('default'),preferred=scene('preferred')}; q.pauseCatalog=true
            end
            local co=focus(e,q,phase=='newcatalog'); equal(run(co),phase=='skin' and 'skin' or 'catalog')
            local ending
            if cancel=='close' or cancel=='finish' then
                q.pauseLeave=true
                ending=coroutine.create(function()
                    if cancel=='close' then q.events['qb-multicharacter:client:closeNUI']()
                    else e.multicharFinishSpawn(vector(50,0,0)) end
                end)
                equal(run(ending),'leave','cancellation still awaiting server')
            elseif cancel=='spawn' then
                assert(loadfile(resource..'/spawn.lua','t',e))()
                q.events['qb-spawn:client:openUI'](true)
            else
                q.pauseEnter=true
                ending=coroutine.create(function()
                    if cancel=='reentry' then q.events['qb-multicharacter:client:chooseChar']()
                    else q.nui['multichar:delete']({citizenid='A'},noop) end
                end)
                equal(run(ending),'enter','re-entry still awaiting server')
            end
            local cameras,loads,ready=q.created,#q.loads,readyCount(q)
            run(co)
            equal(q.created,cameras,'retired await starts no camera')
            equal(#q.loads,loads,'retired await starts no runtime load')
            equal(readyCount(q),ready,'retired await emits no result')
            if ending then run(ending) end
        end)
    end
end
for _,fallback in ipairs({'scene','model','failure'}) do
    H.test('ordinary ' .. fallback .. ' fallback behavior stays intact', function()
        local e,q=host(true)
        if fallback=='scene' then q.catalog.preferred.cameras={} end
        if fallback=='model' then q.failModels.saved=true end
        if fallback=='failure' then q.failModels.saved=true; q.failModels.mp_m_freemode_01=true end
        run(focus(e,q))
        equal(#q.loads,fallback=='scene' and 2 or 3)
        equal(readyCount(q),1)
        local last=q.messages[#q.messages]
        equal(last.data.ok,fallback~='failure'); equal(last.data.scene,'default')
    end)
end
-- Replacing an interpolating flight must release every superseded handle.
for _,phase in ipairs({'lift','travel','descent'}) do
    for _,failure in ipairs({0,2,3,4}) do
        H.test(phase .. ' flight replacement cleans cameras with creation failure ' .. failure, function()
            local e,q=host()
            equal(e.SceneRuntime.previewSpawn({coords=vector(0,0,0)}),true)
            local cfg=e.Config.spawnFlight
            if phase=='lift' then cfg.liftDurationMs=10
            elseif phase=='travel' then cfg.minTravelDurationMs=10; cfg.maxTravelDurationMs=10
            else cfg.descentDurationMs=10 end
            local old=coroutine.create(function() return e.SceneRuntime.previewSpawn({coords=vector(50,0,0)}) end)
            run(old); equal(coroutine.status(old),'suspended','old interpolation waits')
            cfg.liftDurationMs=0; cfg.minTravelDurationMs=0; cfg.maxTravelDurationMs=0; cfg.descentDurationMs=0
            if failure>0 then q.failCreateAt=q.created+failure end
            equal(e.SceneRuntime.previewSpawn({coords=vector(100,0,0)}),true,'replacement or recovery completes')
            local created,active=q.created,q.active
            equal(run(old),false,'older flight retires')
            equal(q.created,created,'older flight creates no new handle')
            equal(q.active,active,'older flight leaves replacement camera active')
            e.SceneRuntime.endMode()
            local alive=0; for _,cam in pairs(q.cameras) do if cam.alive then alive=alive+1 end end
            equal(alive,0,'every owned camera is cleaned')
        end)
    end
end
H.report('preview_lifecycle')
