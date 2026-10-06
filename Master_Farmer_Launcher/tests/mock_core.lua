-- Minimal mock of the Sylvanas `core` API used by the launcher, for running
-- the launcher's Lua under plain LuaJIT. http_get is served by `mock.http`
-- (set per test) and completes on the next mock.pump() - like the real async API.
local mock = { logs = {}, disk = {}, pending = {}, callbacks = {}, requests = {} }

local function C(r, g, b, a)
    return setmetatable({ r, g, b, a or 255 }, { __index = { get = function(s) return s[1], s[2], s[3], s[4] end } })
end
mock.modules = {
    ["common/geometry/vector_2"] = { new = function(x, y)
        assert(type(x) == "number" and type(y) == "number", "vec2 needs numbers"); return { x = x, y = y } end },
    ["common/color"] = { new = C, white = function(a) return C(255, 255, 255, a) end,
        green = function(a) return C(0, 255, 0, a) end },
    ["common/enums"] = { window_enums = {
        font_id = { FONT_NORMAL = 0, FONT_SMALL = 1, FONT_BIG = 2, FONT_SEMI_BIG = 3 },
        window_resizing_flags = { NO_RESIZE = 0 }, window_cross_visuals = { NO_CROSS = 0 },
        window_behaviour_flags = { NO_SCROLLBAR = 0 } } },
}

mock.game_version = "Tbc"
mock.now = 100                -- simulated clock, advanced 0.1 s per pump frame
mock.http = function(url) return 404, "" end

core = {
    time = function() return mock.now end,
    log = function(m) mock.logs[#mock.logs + 1] = m end,
    log_warning = function(m) mock.logs[#mock.logs + 1] = "WARN " .. m end,
    log_error = function(m) mock.logs[#mock.logs + 1] = "ERR " .. m end,
    get_game_version = function() return mock.game_version end,
    is_textbox_focused = function() return false end,
    input = { is_key_pressed = function() return false end },
    graphics = {
        get_screen_size = function() return { x = 1920, y = 1080 } end,
        load_texture = function() return 7 end,
        draw_texture_rect = function(_, p, w, h) assert(p.x and w > 0 and h > 0) end,
        get_text_width = function(t, s) return #t * s * 0.5 end,
        text_2d = function() mock.text2d = (mock.text2d or 0) + 1 end,
    },
    create_data_folder = function() end,
    create_data_file = function(f) mock.disk[f] = mock.disk[f] or "" end,
    write_data_file = function(f, d) mock.disk[f] = d end,
    read_data_file = function(f)
        if mock.disk[f] then return mock.disk[f] end
        local h = mock.data_root and io.open(mock.data_root .. "/" .. f, "rb")
        if not h then return "" end
        local d = h:read("*a"); h:close(); return d
    end,
    http_get = function(url, a, b)
        local cb = b or a
        mock.requests[#mock.requests + 1] = url
        mock.pending[#mock.pending + 1] = function() local code, body = mock.http(url); cb(code, "text/plain", body, "") end
    end,
}
for _, ev in ipairs({ "pre_tick", "update", "render", "render_menu", "render_control_panel",
    "legit_spell_cast", "spell_cast", "game_event", "render_window" }) do
    core["register_on_" .. ev .. "_callback"] = function(fn) mock.callbacks[ev] = fn end
end

--- Simulate `frames` game frames (default 20 s): each one ticks update and
--- completes the HTTP requests issued so far.
function mock.pump(frames)
    for _ = 1, frames or 200 do
        mock.now = mock.now + 0.1
        if mock.callbacks.update then mock.callbacks.update() end
        local batch = mock.pending
        mock.pending = {}
        for _, f in ipairs(batch) do f() end
    end
end

function mock.has_log(pat)
    for _, l in ipairs(mock.logs) do if l:find(pat) then return true end end
    return false
end

function mock.install(root)
    mock.data_root = root .. "/plugin/scripts_data"   -- real GUI textures
    package.path = root .. "/plugin/Master_Farmer/?.lua;" .. package.path
    local orig = require
    require = function(n) return mock.modules[n] or orig(n) end
end

local fails = 0
function mock.check(name, cond)
    print((cond and "PASS " or "FAIL ") .. name)
    if not cond then fails = fails + 1 end
end
function mock.finish()
    print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
    os.exit(fails == 0 and 0 or 1)
end

return mock
