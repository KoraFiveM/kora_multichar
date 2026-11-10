-- Optional FFT development hooks (client). Listed last in fxmanifest.lua and
-- inert unless `setr fft_kora_hooks true`. No other file references FFT.
--
-- kora_multichar's server rules sit behind Kora.callback handlers that take the
-- calling player as their source, so only this resource's client can ask them.
-- This hook sends the same callbacks client.lua sends, limited to an allowlist
-- of callbacks that are read-only or that the server refuses for a player who
-- is already in game. It never opens character select, never selects, creates
-- or deletes a character and never logs the player out.
if GetConvar('fft_kora_hooks', 'false') ~= 'true' then return end

local RUNNER = 'fft'
local VERSION = 1

local function session()
    if GetResourceState(RUNNER) ~= 'started' then return nil end
    local id = LocalPlayer.state.fftSession
    return type(id) == 'string' and id or nil
end

-- Bounded, JSON-safe copy: functions and deep or huge values never leave the VM.
local function summary(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind == 'string' then return #value > 300 and (value:sub(1, 300) .. '...') or value end
    if kind == 'number' or kind == 'boolean' or value == nil then return value end
    if kind ~= 'table' then return '<' .. kind .. '>' end
    if depth >= 3 then return '<table>' end
    local out, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 40 then out['...'] = 'truncated' break end
        out[type(key) == 'number' and key or tostring(key)] = summary(item, depth + 1)
    end
    return out
end

local function scalar(value)
    local kind = type(value)
    if kind == 'string' then return #value <= 64 end
    return value == nil or kind == 'number' or kind == 'boolean'
end

local actions = {}

---Asks the server to enter a cinematic mode, as client.lua does. Returns the
---server's answer as { entered, reason }. A logged-in player is refused; if the
---server ever accepts, the mode is left again at once so the tester is not
---stranded in an isolated routing bucket.
function actions.enterMode(mode)
    if type(mode) ~= 'string' or #mode > 32 then return false, 'Invalid mode', 'invalid' end
    local entered, reason = Kora.callback.trigger('kora_multichar:server:enterMode', mode)
    local left
    if entered == true then left = Kora.callback.trigger('kora_multichar:server:leaveMode') == true end
    return true, { entered = entered == true, reason = summary(reason), leftAgain = left }
end

---Asks the server to leave the cinematic mode (a no-op without a session).
function actions.leaveMode()
    return true, { left = Kora.callback.trigger('kora_multichar:server:leaveMode') == true }
end

---Runs the server's nationality check used by character creation. Read-only.
function actions.validateNationality(value)
    if not scalar(value) then return false, 'Invalid nationality argument', 'invalid' end
    local ok, result = Kora.callback.trigger('kora_multichar:server:validateNationality', value)
    return true, { ok = ok == true, result = summary(result) }
end

---Returns the server's scene registry as { [id] = { label, priority, cameras, entities } }.
function actions.scenes()
    local fetched = Kora.callback.trigger('kora_multichar:server:getScenes')
    if type(fetched) ~= 'table' then return false, 'getScenes answered with ' .. type(fetched), 'rejected' end
    local out, count = {}, 0
    for id, scene in pairs(fetched) do
        count = count + 1
        if count > 64 then break end
        if type(scene) == 'table' then
            out[tostring(id)] = {
                label = summary(scene.label),
                priority = summary(scene.priority),
                cameras = type(scene.cameras) == 'table' and #scene.cameras or 0,
                entities = type(scene.entities) == 'table' and #scene.entities or 0,
            }
        end
    end
    return true, out
end

---The legacy qb-multicharacter server-log callback this resource still answers.
function actions.serverLogs()
    return true, summary(Kora.callback.trigger('qb-multicharacter:server:GetServerLogs'))
end

exports('fftVersion', function() return VERSION end)
exports('fftAction', function(action, ...)
    if GetInvokingResource() ~= RUNNER or not session() then
        return false, 'FFT hooks are disabled or session is not authorised'
    end
    local handler = actions[action]
    if not handler then return false, 'Unsupported FFT action: ' .. tostring(action) end
    return handler(...)
end)
