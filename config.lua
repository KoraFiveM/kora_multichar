Config = {}

Config.buckets = {
    enabled = true,
    disablePopulation = true,
    selectionBase = 1100000,
    creatorBase = 1200000,
}

Config.sceneLimits = {
    maxScenes = 64,
    maxPeds = 8,
    maxVehicles = 6,
    maxProps = 24,
    maxCameras = 8,
    maxCues = 64,
    maxTimelineMs = 120000,
    streamTimeoutMs = 20000,
    worldStreamTimeoutMs = 8000,
}

Config.spawnFlight = {
    liftHeight = 130.0,
    minAltitude = 180.0,
    maxAltitude = 420.0,
    liftDurationMs = 900,
    descentDurationMs = 1450,
    minTravelDurationMs = 1400,
    maxTravelDurationMs = 4200,
    unitsPerSecond = 650.0,
}

Config.spawnSelect = {
    switchCooldownMs = 800,
    settleMs = 1000,
    lockWhileMoving = true,
    hints = {
        previous = 'Previous',
        next = 'Next',
        preview = 'Preview location',
        flying = 'Flying to location…',
        spawn = 'Spawn',
    },
}

-- One-screen select + arrival flight. When enabled, the player picks a
-- character AND an arrival point on the same screen; pressing Play logs the
-- character in and the camera flies from the character scene to the arrival
-- point (Config.spawnFlight tunes the flight), where the ped appears with a
-- particle effect before control returns. When disabled, the original flow is
-- used: Continue, then a separate spawn picker that previews each location.
Config.arrival = {
    enabled = true,
    -- Space cuts the flight short. It still waits for the destination to
    -- stream and still places the ped; only the camera travel is shortened.
    skippable = true,
    -- How long the ped stays invisible after being placed, so the saved
    -- appearance (applied when the character loads) is on before they show.
    settleMs = 350,
    -- Time the ped takes to fade in once the arrival effect starts.
    pedFadeMs = 900,
    -- Time the camera takes to blend back to the gameplay camera.
    handbackMs = 1400,
    -- Added to the arrival point's z when the ped is placed. The ped then
    -- settles onto the ground on its own while still invisible, so this only
    -- changes where it starts falling from.
    zOffset = -0.08,
    -- Particle effect played at the ped's feet. Any loaded ptfx asset works;
    -- set enabled = false for no effect. Pick the look in game.
    ptfx = {
        enabled = true,
        asset = 'scr_rcbarry1',
        effect = 'scr_alien_teleport',
        scale = 1.0,
        zOffset = 0.0,
        -- true: players near the arrival see the effect too. The server relays
        -- it (see kora_multichar:server:arrivalEffect) and plays only what is
        -- configured here, never what a client asks for. false: only the
        -- arriving player sees it.
        synced = true,
        -- How far from the arrival, in metres, another player still sees it.
        syncRadius = 150.0,
        releaseAfterMs = 4000,
    },
}

Config.defaultScene = 'civilian'

Config.previewWatchdogMs = 15000

Config.cameraMode = 'focus'

Config.ui = {
    closeCreateOnBackdrop = false,
    confirmDiscardOnClose = true,
    confirmDisconnect = true,
    brandName = 'Kora',
    showNewSlotBadge = false,
    profile = {
        career      = { label = 'Career' },
        affiliation = { label = 'Affiliation' },
        finances    = { label = 'Finances' },
        birthDate   = { label = 'Birth date', description = '' },
        nationality = { label = 'Nationality', description = 'Place of origin' },
        citizenId   = { label = 'Citizen ID', description = '' },
    },
}

Config.nationalities = {
    'Argentine', 'Australian', 'Austrian', 'Belgian', 'Brazilian', 'British', 'Bulgarian', 'Canadian',
    'Chilean', 'Chinese', 'Colombian', 'Croatian', 'Czech', 'Danish', 'Dutch', 'Egyptian', 'Estonian',
    'Filipino', 'Finnish', 'French', 'German', 'Greek', 'Hungarian', 'Icelandic', 'Indian', 'Irish',
    'Israeli', 'Italian', 'Jamaican', 'Japanese', 'Korean', 'Latvian', 'Lithuanian', 'Mexican',
    'Moroccan', 'New Zealander', 'Nigerian', 'Norwegian', 'Pakistani', 'Peruvian', 'Polish',
    'Portuguese', 'Romanian', 'Russian', 'Saudi', 'Serbian', 'Singaporean', 'Slovak', 'South African',
    'Spanish', 'Swedish', 'Swiss', 'Thai', 'Turkish', 'Ukrainian', 'American', 'Venezuelan', 'Vietnamese',
}
Config.defaultNationality = 'American'
Config.allowFreeTextNationality = false

Config.scenes = {}

Config.logout = {
    enabled = true,
    command = 'logout',
    minimumPermission = 'admin',
}

Config.creator = {
    enabled = true,
    command = 'multicharscene',
    minimumPermission = 'admin',
    moveSpeed = 6.0,
    fastMultiplier = 3.0,
    lookSensitivity = 5.0,
    placementDistance = 8.0,
    library = {
        ped = {
            { 's_m_y_xmech_02', 'Mechanic' }, { 's_m_y_construct_01', 'Construction worker' },
            { 's_m_y_cop_01', 'Police officer' }, { 's_m_m_doctor_01', 'Doctor' },
            { 's_f_y_scrubs_01', 'Nurse' }, { 's_m_m_security_01', 'Security guard' },
            { 'a_m_y_business_01', 'Businessman' }, { 'a_f_y_business_01', 'Businesswoman' },
            { 'a_m_y_hipster_01', 'Hipster (m)' }, { 'a_f_y_hipster_01', 'Hipster (f)' },
            { 'a_m_y_skater_01', 'Skater' }, { 'a_f_y_tourist_01', 'Tourist' },
            { 'a_m_m_hillbilly_01', 'Hillbilly' }, { 's_m_y_dealer_01', 'Dealer' },
            { 'g_m_y_ballaeast_01', 'Ballas member' }, { 'g_m_y_famca_01', 'Families member' },
        },
        vehicle = {
            { 'sultan', 'Sultan' }, { 'buffalo', 'Buffalo' }, { 'dominator', 'Dominator' },
            { 'comet2', 'Comet' }, { 'adder', 'Adder' }, { 'zentorno', 'Zentorno' },
            { 'kuruma', 'Kuruma' }, { 'futo', 'Futo' }, { 'blista', 'Blista' },
            { 'bison', 'Bison' }, { 'sandking', 'Sandking' }, { 'rebel', 'Rebel' },
            { 'police', 'Police cruiser' }, { 'ambulance', 'Ambulance' }, { 'taxi', 'Taxi' },
            { 'bati', 'Bati 801' }, { 'sanchez', 'Sanchez' }, { 'faggio', 'Faggio' },
        },
        prop = {
            { 'prop_tool_box_04', 'Toolbox' }, { 'prop_toolchest_05', 'Tool chest' },
            { 'prop_bin_08', 'Bin' }, { 'prop_bench_01a', 'Bench' },
            { 'prop_table_03', 'Table' }, { 'prop_chair_01a', 'Chair' },
            { 'prop_laptop_01a', 'Laptop' }, { 'prop_generator_03b', 'Generator' },
            { 'prop_roadcone02a', 'Road cone' }, { 'prop_barrier_work06a', 'Work barrier' },
            { 'prop_beach_fire', 'Campfire' }, { 'prop_cs_beer_bot_01', 'Beer bottle' },
        },
    },
}

Config.spawns = {
    {
        id = 'legion',
        coords = vector4(195.17, -933.77, 30.69, 144.0), label = 'Legion Square',
        description = 'The centre of Los Santos, close to shops, transit, and city life.',
        preview = { camera = vector3(219.0, -914.0, 45.0), lookAt = vector3(195.17, -933.77, 30.69) },
    },
    {
        id = 'pillbox',
        coords = vector4(307.7, -595.5, 43.28, 90.0), label = 'Pillbox Hill',
        description = 'Arrive beside Pillbox Hill Medical Center in central Los Santos.',
        preview = { camera = vector3(331.0, -578.0, 58.0), lookAt = vector3(307.7, -595.5, 43.28) },
    },
    {
        id = 'sandy',
        coords = vector4(1839.7, 3672.8, 34.28, 210.0), label = 'Sandy Shores',
        description = 'A quieter start in Blaine County near the airfield and medical center.',
        preview = { camera = vector3(1814.0, 3688.0, 50.0), lookAt = vector3(1839.7, 3672.8, 34.28) },
    },
    {
        id = 'paleto',
        coords = vector4(-108.4, 6431.5, 31.6, 227.6), label = 'Paleto Bay',
        description = 'Begin on the north coast among Paleto Bay businesses and services.',
        preview = { camera = vector3(-85.0, 6407.0, 49.0), lookAt = vector3(-108.4, 6431.5, 31.6) },
    },
}

Config.defaultSpawn = Config.spawns[1].coords

Config.newCharacter = {
    resetAppearance = true,
}
