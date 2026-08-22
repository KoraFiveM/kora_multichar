fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbmultichar'
author 'Jamie'
version '2.0.0'
description 'Custom full-screen character selection for qbcore'

dependency 'qblib'
dependency 'qbcore'

-- This resource now fully implements both legacy UIs -- character select AND
-- spawn selection -- unlike qbcore, which deliberately does NOT provide
-- 'qb-multicharacter' (see qbcore/fxmanifest.lua's comment: hijacking a name
-- you don't fully replace would silently break a real UI resource a server
-- wants to keep). This one does fully replace them, so it claims both names.
provide 'qb-multicharacter'
provide 'qb-spawn'

ui_page 'html/index.html'

-- A bare trailing '**' does NOT match files in FiveM's resource globber --
-- needs the explicit '/*' (see qblib/fxmanifest.lua's comment on the same issue).
files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

-- Required to reach QB.theme -- see qblib's own AGENTS.md for why this is how
-- a consumer resource pulls in the QB proxy (init.lua). NUI messaging itself
-- goes through the raw natives (SendNUIMessage/RegisterNUICallback) instead
-- of QB.nui.* -- this resource owns its own frame now, and QB.nui.* would
-- dispatch into qblib's own resource VM/frame via the cross-resource export
-- call, not this one.
shared_script '@qblib/init.lua'

client_scripts {
    'config.lua',
    'client.lua',
    'spawn.lua',
}
