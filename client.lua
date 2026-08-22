-- Headless: this resource has no NUI of its own. Character selection is
-- driven entirely through qblib's shared NUI (QB.nui.openMenu/openInputDialog/
-- openAlert), so it automatically matches qblib's theme -- see modules/notify
-- and modules/progressbar in qblib for the same pattern.

-- Mirrors qbcore's own Config.identity.maxCharacters (qbcore/config.lua) --
-- multichar has no direct read access to qbcore's internal Config table, so
-- this is kept in sync by hand. Update alongside that value if it changes.
local MAX_CHARACTERS = 5

-- Suppress qbcore's built-in auto-select/auto-create flow
-- (qbcore/modules/multichar/client.lua) -- must run before its 500ms grace
-- window elapses, which this does trivially since it's top-level code that
-- runs the moment this resource starts.
_G.__qbcoreCharSelectUI = true

---Smallest slot in 1..MAX_CHARACTERS not occupied by an existing character.
---@param characters table[]
---@return integer|nil
local function nextFreeSlot(characters)
    local taken = {}
    for _, character in ipairs(characters) do
        taken[character.cid] = true
    end
    for cid = 1, MAX_CHARACTERS do
        if not taken[cid] then return cid end
    end
    return nil
end

---@param character table `{citizenid, cid, name, charinfo, money, job}`
---@return string
local function characterLabel(character)
    local info = character.charinfo or {}
    local name = (('%s %s'):format(info.firstname or '', info.lastname or '')):match('^%s*(.-)%s*$')
    if name ~= '' then return name end
    return character.name or ('Character ' .. tostring(character.cid))
end

---@param characters table[]
---@return table[] items -- qblib openMenu item schema
local function buildItems(characters)
    local items = {}

    for _, character in ipairs(characters) do
        local name = characterLabel(character)
        items[#items + 1] = {
            id = 'char:' .. character.citizenid,
            label = name,
            description = character.job and character.job.label or nil,
            submenu = {
                title = name,
                items = {
                    { id = 'select:' .. character.citizenid, label = 'Play' },
                    { id = 'delete:' .. character.citizenid, label = 'Delete character' },
                },
            },
        }
    end

    if nextFreeSlot(characters) then
        items[#items + 1] = { id = 'create', label = 'Create character' }
    end

    return items
end

---Blocks (this runs inside a net event's own coroutine) until a character is
---selected or created, then triggers the matching server event and returns.
---A cancelled menu/dialog/alert just loops back to the top -- picking a
---character is mandatory, there's nothing sensible to fall through to.
---@param characters table[]
local function runCharacterSelect(characters)
    while true do
        local result = QB.nui.openMenu(buildItems(characters), 'Select a character')

        if result and not result.cancelled then
            local selectedId = result.selectedId

            if selectedId == 'create' then
                local form = QB.nui.openInputDialog({
                    { id = 'firstname', label = 'First name', type = 'text', required = true },
                    { id = 'lastname', label = 'Last name', type = 'text', required = true },
                }, 'New character')

                if form and not form.cancelled then
                    TriggerServerEvent('qbcore:server:createCharacter', {
                        firstname = form.values.firstname,
                        lastname = form.values.lastname,
                        birthdate = '1990-01-01',
                        gender = 0,
                        nationality = 'USA',
                        phone = tostring(math.random(1000000, 9999999)),
                    }, nextFreeSlot(characters))
                    return
                end
            elseif selectedId:sub(1, 7) == 'select:' then
                TriggerServerEvent('qbcore:server:selectCharacter', selectedId:sub(8))
                return
            elseif selectedId:sub(1, 7) == 'delete:' then
                local citizenid = selectedId:sub(8)
                local confirm = QB.nui.openAlert({
                    title = 'Delete character',
                    message = 'This cannot be undone.',
                    confirmLabel = 'Delete',
                    cancelLabel = 'Cancel',
                    destructive = true,
                })

                if confirm and confirm.confirmed then
                    TriggerServerEvent('qbcore:server:deleteCharacter', citizenid)
                    return
                end
            end
        end
        -- Cancelled (or a sub-flow was itself cancelled): loop back to the menu.
    end
end

RegisterNetEvent('qbcore:client:receiveCharacters', function(characters)
    -- The "shutdown the loading screen after all chars fetched" behavior --
    -- safe to call even if something else already shut it down (e.g. a bare
    -- server's spawnmanager on a previous connect).
    ShutdownLoadingScreen()

    runCharacterSelect(characters or {})
end)

RegisterNetEvent('qbcore:client:characterSelected', function(ok, err)
    if ok then return end -- spawn takes over from here

    QB.nui.openAlert({ title = 'Character select failed', message = err or 'Something went wrong.' })
    TriggerServerEvent('qbcore:server:requestCharacters')
end)

-- Kick off the flow -- the moment this resource starts is the equivalent
-- point qbcore's own (now-suppressed) default flow would have fired at.
TriggerServerEvent('qbcore:server:requestCharacters')
