fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_multichar'
author 'Jamie'
version '0.2.0'
description 'Cinematic character selection, live spawn previews, and scene studio for kora_core'

dependency 'kora_theme'
dependency 'kora_lib'
dependency 'kora_core'

-- This resource now fully implements both legacy UIs -- character select AND
-- spawn selection -- unlike kora_core, which deliberately does NOT provide
-- 'qb-multicharacter' (see kora_core/fxmanifest.lua's comment: hijacking a name
-- you don't fully replace would silently break a real UI resource a server
-- wants to keep). This one does fully replace them, so it claims both names.
provide 'qb-multicharacter'
provide 'qb-spawn'

ui_page 'web/build/index.html'

-- A bare trailing '**' does NOT match files in FiveM's resource globber --
-- needs the explicit '/*' (see kora_lib/fxmanifest.lua's comment on the same issue).
files {
    'web/build/index.html',
    'web/build/**/*',
}

-- Required to reach kora_lib APIs -- see kora_lib's own AGENTS.md for why this is how
-- a consumer resource pulls in the Kora proxy (init.lua). NUI messaging itself
-- goes through the raw natives (SendNUIMessage/RegisterNUICallback) instead
-- of Kora.nui.* -- this resource owns its own frame now, and Kora.nui.* would
-- dispatch into kora_lib's own resource VM/frame via the cross-resource export
-- call, not this one.
shared_scripts {
    '@kora_lib/init.lua',
    'config.lua',
    'shared/scene.lua',
    'scenes.lua',
    'shared/config_registration.lua',
}

server_script 'server.lua'

client_scripts {
    '@kora_theme/client/bridge.lua',
    'scene.lua',
    'client.lua',
    'spawn.lua',
    'creator.lua',
    -- Optional FFT hooks: returns immediately unless fft_kora_hooks is true.
    'fft_hooks.lua'
}

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
