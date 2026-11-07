local function revealCameras(focalOffset, focalLookAt, focalFov, establishingOffset, establishingLookAt, establishingFov, closeOffset, closeLookAt, closeFov)
    establishingOffset = establishingOffset or vector3(focalOffset.x * 1.62, focalOffset.y * 1.62, focalOffset.z + 2.35)
    establishingLookAt = establishingLookAt or focalLookAt
    return {
        {
            id = 'close',
            -- Local +Y is in front of a character facing the scene anchor's
            -- heading, so every reveal opens on the face rather than the back.
            offset = closeOffset or vector3(0.65, 2.65, 1.68),
            lookAt = closeLookAt or vector3(0.0, 0.0, 1.34),
            fov = closeFov or 30.0,
            dof = { near = 0.8, far = 3.2, strength = 0.65 },
        },
        {
            id = 'focal',
            offset = focalOffset,
            lookAt = focalLookAt,
            fov = focalFov or 43.0,
            transitionMs = 2200,
            dof = { near = 2.0, far = 14.0, strength = 0.22 },
        },
        {
            id = 'establishing',
            offset = establishingOffset,
            lookAt = establishingLookAt,
            fov = establishingFov or math.min((focalFov or 43.0) + 9.0, 58.0),
            transitionMs = 2400,
            dof = { near = 4.0, far = 40.0, strength = 0.10 },
        },
    }
end

local function revealTimeline(extraCues, durationMs)
    durationMs = durationMs or 18000
    local cues = {
        { at = 0, type = 'camera', camera = 'close' },
        -- Hold the portrait just long enough to identify the character, then
        -- ease out to the authored job/gang focal composition.
        { at = 1700, type = 'camera', camera = 'focal', transitionMs = 2100 },
        { at = 5200, type = 'camera', camera = 'establishing', transitionMs = 2400 },
        { at = 9400, type = 'camera', camera = 'focal', transitionMs = 2200 },
    }
    for _, cue in ipairs(extraCues or {}) do cues[#cues + 1] = cue end
    -- Return to the portrait before the loop boundary so a looping scene never
    -- hard-cuts from the focal shot back to the opening frame.
    cues[#cues + 1] = { at = durationMs - 3200, type = 'camera', camera = 'close', transitionMs = 1900 }
    return { durationMs = durationMs, loop = true, cues = cues }
end

local bundledScenes = {
    civilian = {
        label = 'Vespucci Beach · Sunset', priority = 0,
        -- Serves two roles, and needs both. The selector makes it the explicit
        -- scene for an unemployed character; being Config.defaultScene makes it
        -- the fallback for any job or gang nobody has authored a scene for.
        -- Priority 0 keeps it the lowest bidder, so a configured job or gang
        -- scene always outranks it -- including for an unemployed character who
        -- is in a gang.
        selectors = { { job = 'unemployed' } },
        -- Dry sand east of the old offshore anchor. Local -Y runs out
        -- toward the water, keeping both moving riders behind the character.
        anchor = vector4(-1560.5, -1180.5, 2.2, 270.0),
        environment = { hour = 19, minute = 10, weather = 'EXTRASUNNY', timecycle = 'scanline_cam_cheap', strength = 0.06 },
        character = { offset = vector4(0.0, 0.0, 0.0, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        entities = {
            { id = 'jetski1', type = 'vehicle', model = 'seashark', offset = vector4(-7.0, -48.0, -1.0, 96.0), collision = true, frozen = false, snapToGround = false, snapToWater = true, vehicle = { engine = true, lights = false, anchored = false } },
            { id = 'jetski2', type = 'vehicle', model = 'seashark3', offset = vector4(8.0, -55.0, -1.0, 264.0), collision = true, frozen = false, snapToGround = false, snapToWater = true, vehicle = { engine = true, lights = false, anchored = false, primaryColor = 88, secondaryColor = 88 } },
            { id = 'rider1', type = 'ped', model = 'a_m_y_jetski_01', offset = vector4(-7.0, -48.0, -0.8, 96.0), frozen = false, snapToGround = false, seat = { vehicle = 'jetski1', index = -1 } },
            { id = 'rider2', type = 'ped', model = 'a_f_y_beach_01', offset = vector4(8.0, -55.0, -0.8, 264.0), frozen = false, snapToGround = false, seat = { vehicle = 'jetski2', index = -1 } },
            { id = 'walker', type = 'ped', model = 'a_m_y_beach_02', offset = vector4(-5.0, 1.5, 0.0, 70.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
            { id = 'parasol', type = 'prop', model = 'prop_beach_parasol_02', offset = vector4(5.2, -1.5, -0.05, 15.0) },
            { id = 'towel', type = 'prop', model = 'prop_beach_towel_02', offset = vector4(4.4, -1.1, -0.03, 10.0) },
        },
        cameras = revealCameras(
            vector3(7.2, 7.8, 3.45), vector3(0.0, -3.0, 0.85), 43.0,
            vector3(13.5, 15.5, 7.0), vector3(0.0, -9.0, 0.45), 53.0
        ),
        timeline = revealTimeline({
            { at = 350, type = 'vehicleRoute', target = 'rider1', destination = vector3(34.0, -54.0, -0.8), speed = 12.0, stoppingRange = 4.0, snapToWater = true },
            { at = 350, type = 'vehicleRoute', target = 'rider2', destination = vector3(-34.0, -61.0, -0.8), speed = 11.0, stoppingRange = 4.0, snapToWater = true },
            { at = 9200, type = 'vehicleRoute', target = 'rider1', destination = vector3(-7.0, -48.0, -0.8), speed = 12.0, stoppingRange = 4.0, snapToWater = true },
            { at = 9200, type = 'vehicleRoute', target = 'rider2', destination = vector3(8.0, -55.0, -0.8), speed = 11.0, stoppingRange = 4.0, snapToWater = true },
        }),
    },

    police = {
        label = 'Strawberry 24/7 · Robbery in Progress', priority = 200,
        selectors = { { job = 'police' } },
        -- The forecourt outside the Strawberry 24/7 gives the scene open sky,
        -- useful depth, and enough space for the camera safety fan to reframe.
        anchor = vector4(-61.25, -1759.2, 29.35, 50.0),
        environment = { hour = 23, minute = 18, weather = 'CLEAR', timecycle = 'scanline_cam_cheap', strength = 0.10 },
        character = { offset = vector4(0.0, 0.0, 0.0, 0.0), animation = { dict = 'random@arrests', name = 'generic_radio_chatter', flag = 49 } },
        entities = {
            { id = 'unit1', type = 'vehicle', model = 'police3', offset = vector4(-5.4, 3.1, -0.1, -32.0), vehicle = { engine = true, lights = true, siren = true, mutedSiren = true } },
            { id = 'getaway', type = 'vehicle', model = 'sultan', offset = vector4(5.2, 6.0, -0.1, 108.0), vehicle = { engine = true, lights = true, doors = { [0] = true } } },
            { id = 'backup', type = 'ped', model = 's_m_y_cop_01', offset = vector4(-2.4, 2.1, 0.0, -20.0), animation = { dict = 'random@arrests', name = 'generic_radio_chatter', flag = 49 } },
            { id = 'suspect', type = 'ped', model = 'g_m_y_mexgoon_02', offset = vector4(2.8, 3.4, 0.0, 180.0), animation = { dict = 'missminuteman_1ig_2', name = 'handsup_base', flag = 49 } },
            { id = 'bag', type = 'prop', model = 'prop_cs_heist_bag_02', offset = vector4(3.2, 4.0, 0.05, 20.0) },
        },
        cameras = revealCameras(vector3(-9.2, 8.7, 4.0), vector3(-0.2, 2.8, 0.85), 42.0),
        timeline = revealTimeline({
            { at = 350, type = 'vehicleState', target = 'unit1', lights = true, siren = true, mutedSiren = true },
            { at = 6200, type = 'nativeSound', target = 'unit1', name = '5_SEC_WARNING', set = 'HUD_MINI_GAME_SOUNDSET' },
        }),
    },

    ambulance = {
        label = 'Pillbox · Active Medical Response', priority = 200,
        selectors = { { job = 'ambulance' } },
        -- Centers the ambulance on Pillbox's known outdoor vehicle bay rather
        -- than rotating it underneath the hospital overhang.
        anchor = vector4(298.4, -572.1, 43.18, 35.0),
        environment = { hour = 20, minute = 5, weather = 'CLEAR', timecycle = 'scanline_cam_cheap', strength = 0.07 },
        character = { offset = vector4(0.0, 0.0, 0.0, 0.0), animation = { dict = 'mini@cpr@char_a@cpr_str', name = 'cpr_pumpchest', flag = 1 } },
        entities = {
            { id = 'ambulance', type = 'vehicle', model = 'ambulance', offset = vector4(-4.65, 0.0, 0.0, 180.0), collision = true, vehicle = { engine = true, lights = true, siren = true, mutedSiren = true, doors = { [2] = true, [3] = true } } },
            { id = 'patient', type = 'ped', model = 'a_m_y_business_02', offset = vector4(-1.0, 1.55, 0.0, 180.0), animation = { dict = 'combat@damage@writhe', name = 'writhe_loop', flag = 1 } },
            { id = 'medic_assist', type = 'ped', model = 's_m_m_paramedic_01', offset = vector4(1.1, 1.1, 0.0, 255.0), animation = { dict = 'amb@medic@standing@kneel@base', name = 'base', flag = 1 } },
            { id = 'medic_lead', type = 'ped', model = 's_m_m_paramedic_01', offset = vector4(2.8, -0.8, 0.0, 210.0), animation = { dict = 'random@arrests', name = 'generic_radio_chatter', flag = 49 } },
            { id = 'stretcher', type = 'prop', model = 'v_med_emptybed', offset = vector4(2.8, 2.4, 0.1, 90.0) },
            { id = 'trauma_kit', type = 'prop', model = 'prop_ld_health_pack', offset = vector4(0.55, 1.8, 0.08, 15.0) },
        },
        cameras = revealCameras(
            vector3(8.8, 7.8, 4.1), vector3(-1.4, 0.9, 0.8), 41.0,
            vector3(16.5, 13.2, 8.2), vector3(-1.3, 0.4, 0.65), 54.0,
            -- The default portrait aims at standing head height; the CPR pose is
            -- kneeling, so the character fell to the bottom of the frame. Stay
            -- inside the portrait's 3.2 depth-of-field far limit (blurred
            -- beyond it) and use a wider fov to keep the pose in shot.
            vector3(0.7, 2.7, 1.2), vector3(0.0, 0.0, 0.6), 38.0
        ),
        timeline = revealTimeline({
            { at = 450, type = 'vehicleState', target = 'ambulance', lights = true, siren = true, mutedSiren = true },
            { at = 700, type = 'animation', target = 'character', dict = 'mini@cpr@char_a@cpr_str', name = 'cpr_pumpchest', flag = 1, durationMs = 12500 },
            { at = 900, type = 'animation', target = 'medic_assist', dict = 'amb@medic@standing@kneel@base', name = 'base', flag = 1, durationMs = 12500 },
            { at = 11200, type = 'vehicleState', target = 'ambulance', lights = true, siren = true, mutedSiren = true, doors = { [2] = true, [3] = true } },
        }),
    },

    mechanic = {
        label = 'Benny\'s Workshop', priority = 200,
        selectors = { { job = 'mechanic' } },
        anchor = vector4(-211.55, -1324.55, 30.89, 270.0),
        environment = { hour = 14, minute = 30, weather = 'EXTRASUNNY' },
        character = { offset = vector4(0.0, 0.0, 0.0, 0.0), scenario = 'WORLD_HUMAN_HAMMERING' },
        entities = {
            { id = 'project', type = 'vehicle', model = 'sultan', offset = vector4(-4.2, 2.4, 0.0, 90.0), vehicle = { engine = false, doors = { [4] = true } } },
            { id = 'mechanic', type = 'ped', model = 's_m_y_xmech_02', offset = vector4(-2.5, 1.2, 0.0, 95.0), scenario = 'WORLD_HUMAN_VEHICLE_MECHANIC' },
            { id = 'tools', type = 'prop', model = 'prop_tool_box_04', offset = vector4(2.4, 1.5, 0.0, 0.0) },
        },
        cameras = revealCameras(vector3(7.4, 6.2, 3.25), vector3(-2.0, 1.8, 0.8), 41.0),
        timeline = revealTimeline({
            { at = 6200, type = 'particle', target = 'project', asset = 'core', effect = 'ent_sht_electrical_box', scale = 0.55, durationMs = 2200 },
            { at = 6500, type = 'nativeSound', target = 'project', name = 'Drill', set = 'DLC_HEIST_FLEECA_SOUNDSET' },
        }),
    },

    ballas = {
        label = 'Davis', priority = 100,
        selectors = { { gang = 'ballas' } },
        anchor = vector4(104.84, -1940.73, 20.8, 320.0),
        environment = { hour = 19, minute = 10, weather = 'CLEAR' },
        character = { offset = vector4(0.0, 0.0, 0.0, 0.0), scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
        entities = {
            { id = 'lowrider', type = 'vehicle', model = 'buccaneer2', offset = vector4(-4.0, 2.8, 0.0, 25.0), vehicle = { engine = true, lights = true, primaryColor = 145, secondaryColor = 145 } },
            { id = 'member1', type = 'ped', model = 'g_m_y_ballaeast_01', offset = vector4(3.0, 2.0, 0.0, 220.0), scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
            { id = 'member2', type = 'ped', model = 'g_m_y_ballaorig_01', offset = vector4(4.2, 0.8, 0.0, 205.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },
        cameras = revealCameras(vector3(-8.0, 7.2, 3.45), vector3(0.0, 1.8, 0.9), 42.0),
        timeline = revealTimeline(),
    },

    vagos = {
        label = 'Rancho', priority = 100,
        selectors = { { gang = 'vagos' } },
        anchor = vector4(332.2, -2018.1, 22.35, 140.0),
        environment = { hour = 18, minute = 15, weather = 'EXTRASUNNY' },
        character = { offset = vector4(0.0, 0.0, 0.0, 0.0), scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
        entities = {
            { id = 'lowrider', type = 'vehicle', model = 'tornado3', offset = vector4(-4.2, 2.5, 0.0, 30.0), vehicle = { engine = true, lights = false, primaryColor = 88, secondaryColor = 88 } },
            { id = 'member1', type = 'ped', model = 'g_m_y_mexgoon_01', offset = vector4(3.0, 2.0, 0.0, 210.0), scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
            { id = 'member2', type = 'ped', model = 'g_m_y_mexgoon_02', offset = vector4(4.0, 0.7, 0.0, 200.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },
        cameras = revealCameras(vector3(7.5, 7.0, 3.5), vector3(0.0, 1.7, 0.9), 42.0),
        timeline = revealTimeline(),
    },
}

for id, definition in pairs(bundledScenes) do
    if Config.scenes[id] == nil then Config.scenes[id] = definition end
end
