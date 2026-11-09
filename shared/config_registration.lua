local sceneOptions = {}
for id, scene in pairs(Config.scenes) do
    sceneOptions[#sceneOptions + 1] = { value = id, label = scene.label or id }
end
table.sort(sceneOptions, function(a, b) return a.value < b.value end)

local defaultScene = Config.defaultScene
Config.defaultScene = Kora.config.enum(Config.defaultScene, {
    label = 'Default scene',
    description = 'Selects the fallback character-selection scene used when no job-specific or gang-specific scene matches the character. The choice controls the authored camera, position, and presentation loaded for that fallback.',
    options = sceneOptions,
})
Config.scenes = Kora.config.map(Config.scenes, Kora.config.object({}), {
    label = 'Character-selection scenes',
    description = 'Maps each stable scene ID to its authored character position, camera path, environment, labels, and presentation settings. Job and gang scene selectors refer to these IDs; keep the selected default scene present and restart qbmultichar after editing scene definitions.',
    requiredKeys = { defaultScene },
})
Config.previewWatchdogMs = Kora.config.number(Config.previewWatchdogMs, {
    min = 0, live = true,
    label = 'Preview watchdog (ms)',
    description = 'How long a character-select preview may stay on the loading cover before the interface gives up, hides the cover and shows an error. Set to 0 to disable the watchdog. Applies the next time character select opens.',
})
Config.cameraMode = Kora.config.enum(Config.cameraMode, {
    live = true,
    label = 'Character-select camera mode',
    description = 'Focus keeps the camera on the previewed ped (the selected character, or the create-slot ped when there are no characters) and only moves it when the selection changes. Cycle keeps the original behaviour, where the scene timeline loops through its close, focal and establishing camera angles. Applies the next time a character preview loads.',
    options = {
        { value = 'focus', label = 'Focus on the selected ped' },
        { value = 'cycle', label = 'Cycle camera angles' },
    },
})
Config.ui.closeCreateOnBackdrop = Kora.config.boolean(Config.ui.closeCreateOnBackdrop, {
    live = true,
    label = 'Close Create Identity on outside click',
    description = 'When enabled, clicking outside the Create Identity dialog closes it. When disabled, only the close button, Cancel or Escape closes it, so a stray click cannot discard typed details. Applies the next time character select opens.',
})
Config.ui.confirmDiscardOnClose = Kora.config.boolean(Config.ui.confirmDiscardOnClose, {
    live = true,
    label = 'Confirm before discarding Create Identity details',
    description = 'When enabled, closing the Create Identity dialog with the close button, Cancel or Escape after typing asks "Discard?" inside the dialog first. When disabled it closes immediately and the typed details are cleared. Applies the next time character select opens.',
})
Config.ui.brandName = Kora.config.string(Config.ui.brandName, {
    live = true, minLength = 1, maxLength = 32,
    label = 'Brand name',
    description = 'The brand text shown above "Choose your story" and on the loading cover. Applies the next time character select opens.',
})
Config.ui.showNewSlotBadge = Kora.config.boolean(Config.ui.showNewSlotBadge, {
    live = true,
    label = 'Show NEW badge on the free character slot',
    description = 'When enabled, the "Available character slot" card carries a NEW badge. Off by default. Applies the next time character select opens.',
})
Config.ui.profile.career.label = Kora.config.string(Config.ui.profile.career.label, {
    live = true, minLength = 1, maxLength = 32,
    label = 'Profile card title: Career',
    description = 'The title of the Career card on the character Profile panel. Applies the next time character select opens.',
})
Config.ui.profile.affiliation.label = Kora.config.string(Config.ui.profile.affiliation.label, {
    live = true, minLength = 1, maxLength = 32,
    label = 'Profile card title: Affiliation',
    description = 'The title of the Affiliation card on the character Profile panel. Applies the next time character select opens.',
})
Config.ui.profile.finances.label = Kora.config.string(Config.ui.profile.finances.label, {
    live = true, minLength = 1, maxLength = 32,
    label = 'Profile card title: Finances',
    description = 'The title of the Finances card on the character Profile panel. Applies the next time character select opens.',
})
Config.ui.profile.birthDate.label = Kora.config.string(Config.ui.profile.birthDate.label, {
    live = true, minLength = 1, maxLength = 32,
    label = 'Profile card title: Birth date',
    description = 'The title of the Birth date card on the character Profile panel. Applies the next time character select opens.',
})
Config.ui.profile.birthDate.description = Kora.config.string(Config.ui.profile.birthDate.description, {
    live = true, maxLength = 48,
    label = 'Profile card description: Birth date',
    description = 'The small line under the Birth date value on the character Profile panel. Leave it empty to show no description; the card then collapses to its title and value. Applies the next time character select opens.',
})
Config.ui.profile.nationality.label = Kora.config.string(Config.ui.profile.nationality.label, {
    live = true, minLength = 1, maxLength = 32,
    label = 'Profile card title: Nationality',
    description = 'The title of the Nationality card on the character Profile panel. Applies the next time character select opens.',
})
Config.ui.profile.nationality.description = Kora.config.string(Config.ui.profile.nationality.description, {
    live = true, maxLength = 48,
    label = 'Profile card description: Nationality',
    description = 'The small line under the Nationality value on the character Profile panel. Leave it empty to show no description; the card then collapses to its title and value. Applies the next time character select opens.',
})
Config.ui.profile.citizenId.label = Kora.config.string(Config.ui.profile.citizenId.label, {
    live = true, minLength = 1, maxLength = 32,
    label = 'Profile card title: Citizen ID',
    description = 'The title of the Citizen ID card on the character Profile panel. Applies the next time character select opens.',
})
Config.ui.profile.citizenId.description = Kora.config.string(Config.ui.profile.citizenId.description, {
    live = true, maxLength = 48,
    label = 'Profile card description: Citizen ID',
    description = 'The small line under the Citizen ID value on the character Profile panel. Leave it empty to show no description; the card then collapses to its title and value. Applies the next time character select opens.',
})
Config.nationalities = Kora.config.list(Config.nationalities, Kora.config.string('', { minLength = 2, maxLength = 32 }), {
    live = true,
    label = 'Nationality choices',
    description = 'The nationalities offered in the Create Identity dropdown. The server rejects a created character whose nationality is not in this list. An empty list turns the field into free text. Applies the next time character select opens.',
})
Config.defaultNationality = Kora.config.string(Config.defaultNationality, {
    live = true, maxLength = 32,
    label = 'Default nationality',
    description = 'The nationality selected when Create Identity opens. If it is not in the nationality list the first list entry is used. Applies the next time character select opens.',
})
Config.allowFreeTextNationality = Kora.config.boolean(Config.allowFreeTextNationality, {
    live = true,
    label = 'Allow free-text nationality',
    description = 'When enabled, players type their nationality (the list is offered as suggestions) and the server accepts any 2 to 32 character value. When disabled the dropdown is the only way to choose and the server rejects values outside the list. Applies the next time character select opens.',
})
Config.arrival.enabled = Kora.config.boolean(Config.arrival.enabled, {
    live = true,
    label = 'Pick character and arrival point on one screen',
    description = 'When enabled, character select also offers the arrival points; Play logs the character in and the camera flies from the character scene to the chosen arrival point, where the ped appears with a particle effect. When disabled, Continue opens the separate spawn picker that previews every location. Applies the next time character select opens.',
})
Config.arrival.skippable = Kora.config.boolean(Config.arrival.skippable, {
    live = true,
    label = 'Allow skipping the arrival flight',
    description = 'When enabled, pressing Space during the arrival flight cuts the camera travel short. The destination still streams in and the ped is still placed normally.',
})
Config.arrival.settleMs = Kora.config.number(Config.arrival.settleMs, {
    min = 0, max = 3000, live = true,
    label = 'Arrival settle time (ms)',
    description = 'How long the ped stays invisible after being placed at the arrival point, so their saved appearance is applied before they appear.',
})
Config.arrival.pedFadeMs = Kora.config.number(Config.arrival.pedFadeMs, {
    min = 0, max = 5000, live = true,
    label = 'Arrival ped fade-in (ms)',
    description = 'How long the ped takes to fade in when the arrival effect starts. 0 shows the ped instantly.',
})
Config.arrival.handbackMs = Kora.config.number(Config.arrival.handbackMs, {
    min = 0, max = 5000, live = true,
    label = 'Camera hand-back time (ms)',
    description = 'How long the camera takes to blend from the arrival shot back to the normal gameplay camera.',
})
Config.arrival.zOffset = Kora.config.number(Config.arrival.zOffset, {
    min = -3.0, max = 3.0, live = true,
    label = 'Arrival height offset',
    description = 'Added to the arrival point\'s z when the ped is placed, in metres. The ped is not frozen, so it settles onto the ground while still invisible; this only changes the height it starts from. Use a negative value to start lower.',
})
Config.arrival.ptfx.enabled = Kora.config.boolean(Config.arrival.ptfx.enabled, {
    live = true,
    label = 'Play an effect when the ped arrives',
    description = 'When enabled, the particle effect below plays at the ped when they arrive. If the asset or effect cannot be loaded the arrival continues without it.',
})
Config.arrival.ptfx.synced = Kora.config.boolean(Config.arrival.ptfx.synced, {
    live = true,
    label = 'Show the arrival effect to nearby players',
    description = 'When enabled, players near the arrival see the effect too: the server checks the request and tells nearby clients to play the effect configured here. When disabled, only the arriving player sees it. Applies to the next arrival.',
})
Config.arrival.ptfx.syncRadius = Kora.config.number(Config.arrival.ptfx.syncRadius, {
    min = 10.0, max = 500.0, live = true,
    label = 'Arrival effect visibility radius',
    description = 'How far from the arrival point, in metres, another player must be to be shown the effect. Only used when the effect is shown to nearby players.',
})
Config.arrival.ptfx.asset = Kora.config.string(Config.arrival.ptfx.asset, {
    live = true, minLength = 1, maxLength = 64,
    label = 'Arrival effect asset',
    description = 'The particle asset (ptfx dictionary) that holds the arrival effect, for example scr_rcbarry1.',
})
Config.arrival.ptfx.effect = Kora.config.string(Config.arrival.ptfx.effect, {
    live = true, minLength = 1, maxLength = 64,
    label = 'Arrival effect name',
    description = 'The effect to play from the asset above, for example scr_alien_teleport.',
})
Config.arrival.ptfx.scale = Kora.config.number(Config.arrival.ptfx.scale, {
    min = 0.1, max = 10.0, live = true,
    label = 'Arrival effect scale',
    description = 'Size multiplier for the arrival effect.',
})
Config.arrival.ptfx.zOffset = Kora.config.number(Config.arrival.ptfx.zOffset, {
    min = -5.0, max = 5.0, live = true,
    label = 'Arrival effect height offset',
    description = 'Raises or lowers the arrival effect relative to the ped\'s feet, in metres.',
})
Config.buckets.enabled = Kora.config.boolean(Config.buckets.enabled, {
    live = true,
    label = 'Isolate character select in a personal routing bucket',
    description = 'When enabled, character select, spawn selection and the scene studio move the player into a private routing bucket and return them to their previous bucket afterwards. When disabled the player stays in whatever bucket they were in and is never moved. Applies the next time a session starts.',
})
Config.buckets.disablePopulation = Kora.config.boolean(Config.buckets.disablePopulation, {
    live = true,
    label = 'Disable ambient population in the character-select bucket',
    description = 'When enabled, ambient peds and vehicles (traffic, jet skis, pedestrians) are switched off inside the private character-select bucket so they do not wander through the preview scene. Only that personal bucket is affected, never the normal world. Has no effect when bucket isolation is disabled. Applies the next time a session starts.',
})
Config = Kora.config.adopt(Config)
