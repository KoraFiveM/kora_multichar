-- The bundled scenes have finished extending Config.scenes by this point, so
-- they are included in the resource-owned kora_lib configuration catalog.
local sceneOptions = {}
for id, scene in pairs(Config.scenes) do
    sceneOptions[#sceneOptions + 1] = { value = id, label = scene.label or id }
end
table.sort(sceneOptions, function(a, b) return a.value < b.value end)

local defaultScene = Config.defaultScene
Config.defaultScene = QB.config.enum(Config.defaultScene, {
    label = 'Default scene',
    description = 'Selects the fallback character-selection scene used when no job-specific or gang-specific scene matches the character. The choice controls the authored camera, position, and presentation loaded for that fallback.',
    options = sceneOptions,
})
Config.scenes = QB.config.map(Config.scenes, QB.config.object({}), {
    label = 'Character-selection scenes',
    description = 'Maps each stable scene ID to its authored character position, camera path, environment, labels, and presentation settings. Job and gang scene selectors refer to these IDs; keep the selected default scene present and restart qbmultichar after editing scene definitions.',
    requiredKeys = { defaultScene },
})
Config.previewWatchdogMs = QB.config.number(Config.previewWatchdogMs, {
    min = 0, live = true,
    label = 'Preview watchdog (ms)',
    description = 'How long a character-select preview may stay on the loading cover before the interface gives up, hides the cover and shows an error. Set to 0 to disable the watchdog. Applies the next time character select opens.',
})
Config.cameraMode = QB.config.enum(Config.cameraMode, {
    live = true,
    label = 'Character-select camera mode',
    description = 'Focus keeps the camera on the previewed ped (the selected character, or the create-slot ped when there are no characters) and only moves it when the selection changes. Cycle keeps the original behaviour, where the scene timeline loops through its close, focal and establishing camera angles. Applies the next time a character preview loads.',
    options = {
        { value = 'focus', label = 'Focus on the selected ped' },
        { value = 'cycle', label = 'Cycle camera angles' },
    },
})
Config.ui.closeCreateOnBackdrop = QB.config.boolean(Config.ui.closeCreateOnBackdrop, {
    live = true,
    label = 'Close Create Identity on outside click',
    description = 'When enabled, clicking outside the Create Identity dialog closes it. When disabled, only the close button, Cancel or Escape closes it, so a stray click cannot discard typed details. Applies the next time character select opens.',
})
Config.ui.confirmDiscardOnClose = QB.config.boolean(Config.ui.confirmDiscardOnClose, {
    live = true,
    label = 'Confirm before discarding Create Identity details',
    description = 'When enabled, closing the Create Identity dialog with the close button, Cancel or Escape after typing asks "Discard?" inside the dialog first. When disabled it closes immediately and the typed details are cleared. Applies the next time character select opens.',
})
Config = QB.config.adopt(Config)
