-- The bundled scenes have finished extending Config.scenes by this point, so
-- they are included in the resource-owned qblib configuration catalog.
local sceneOptions = {}
for id, scene in pairs(Config.scenes) do
    sceneOptions[#sceneOptions + 1] = { value = id, label = scene.label or id }
end
table.sort(sceneOptions, function(a, b) return a.value < b.value end)

Config.defaultScene = QB.config.enum(Config.defaultScene, {
    label = 'Default scene',
    description = 'Selects the fallback character-selection scene used when no job-specific or gang-specific scene matches the character. The choice controls the authored camera, position, and presentation loaded for that fallback.',
    options = sceneOptions,
})
Config = QB.config.adopt(Config)
