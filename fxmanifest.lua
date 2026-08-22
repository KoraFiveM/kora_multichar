fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'multichar'
author 'Jamie'
version '1.0.0'
description 'Character selection for qbcore, headless -- driven entirely through qblib''s shared NUI (menus/dialogs/alerts)'

dependency 'qblib'
dependency 'qbcore'

-- No ui_page/files of its own: this resource is headless, same as qblib's
-- own notify/progressbar modules -- everything renders through qblib's
-- shared NUI frame via QB.nui.openMenu/openInputDialog/openAlert, so it
-- automatically matches qblib's theme instead of maintaining a parallel one.

-- Required to reach QB.theme/QB.nui -- see qblib's own AGENTS.md for why this
-- is how a consumer resource pulls in the QB proxy (init.lua).
shared_script '@qblib/init.lua'

client_script 'client.lua'
