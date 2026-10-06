-- MF_PathToolV3 Rotation tab: renders the REAL gui.lua "rotation" tab with a
-- recording stand-in for ui.lua and checks layout, rows and click behaviour.
-- Run:  luajit tests/test_rotation_gui.lua <project root>
local ROOT = arg[1] or "."
local SRC = ROOT .. "/products_src/mf_route_tool/"
package.path = SRC .. "?.lua;" .. package.path

local fails = 0
local function check(name, cond, extra)
    print((cond and "PASS " or "FAIL ") .. name .. ((not cond and extra) and ("   [" .. tostring(extra) .. "]") or ""))
    if not cond then fails = fails + 1 end
end

local T = 100
local BOOK = { [133] = "Fireball", [3140] = "Fireball", [168] = "Frost Armor", [20572] = "Blood Fury",
    [2136] = "Fire Blast" }
local BASE = { [3140] = 133 }
local player = {
    is_valid = function() return true end, get_level = function() return 10 end,
    get_position = function() return { x = 0, y = 0, z = 0 } end,
}
core = {
    log = function() end, log_error = function(m) print("ERR " .. m) end, log_warning = function() end,
    time = function() return T end, get_map_id = function() return 1 end,
    graphics = { add_notification = function() end },
    object_manager = { get_local_player = function() return player end, get_visible_objects = function() return {} end },
    spell_book = {
        get_spells = function() local t = {} for id in pairs(BOOK) do t[#t + 1] = id end return t end,
        has_spell = function(id) return BOOK[id] ~= nil end,
        get_spell_name = function(id) return BOOK[id] end,
        get_base_spell_id = function(id) return BASE[id] or id end,
        spell_has_attribute = function() return false end,
        is_spell_position_cast = function() return false end,
        get_spell_base_cooldown = function(id) return { cooldown_ms = id == 2136 and 8000 or 0 } end,
    },
    input = {}, game_ui = {},
    create_data_file = function() end, write_data_file = function() end,
    read_data_file = function() return "" end,
}

local function el(v)
    return { v = v, get_state = function(self) return self.v == true end, get = function(self) return self.v end,
        set = function(self, x) self.v = x end, get_text = function() return "" end,
        is_reading_input = function() return false end, set_buffer = function() end }
end

-- Recording ui.lua stand-in -------------------------------------------------
local fake = { elements = {}, tabs = nil, on_tabs = {}, status = nil, texts = {}, rows = {},
    click_label = nil, launch_click = nil, id_text = nil, actions = {} }
local Menu = {}
Menu.__index = Menu
local function reg(self, id, kind, def, opts)
    local e = el(def)
    self.elements[id] = { kind = kind, element = e, label = opts and opts.label, tab = opts and opts.tab,
        skip_draw = opts and opts.skip_draw }
    return e
end
function Menu:checkbox(id, d, o) return reg(self, id, "checkbox", d, o) end
function Menu:slider_int(id, a, b, d, o) return reg(self, id, "slider", d, o) end
function Menu:slider_float(id, a, b, d, o) return reg(self, id, "slider", d, o) end
function Menu:combobox(id, d, items, o) return reg(self, id, "combo", d, o) end
function Menu:text_input(id, save, o) return reg(self, id, "text", "", o) end
function Menu:keybind(id, k, t, o) return reg(self, id, "keybind", false, o) end
function Menu:button(id, o) return reg(self, id, "button", false, o) end
function Menu:element(id) return self.elements[id] and self.elements[id].element end
function Menu:on_tab(id, fn) fake.on_tabs[id] = fn end
function Menu:set_status(items) fake.status = items end
function Menu:set_actions(a) self.actions = a end
function Menu:add_popup() end
function Menu:set_combobox_items() end
function Menu:set_visible() end
function Menu:is_closed() return false end
function Menu:draw() end
function Menu:is_binding_key() return false end
function Menu:is_id_field_focused() return false end
function Menu:is_popup_open() return false end
function Menu:draw_checkbox_row(win, rec, x, y, w)
    fake.rows[#fake.rows + 1] = rec.label
    if fake.click_label == rec.label then rec.element:set(not rec.element:get_state()) end
    return y + 42
end
function Menu:draw_launcher(win, x, y, w, h, label)
    fake.texts[#fake.texts + 1] = "[btn] " .. label
    return fake.launch_click == label
end
function Menu:draw_id_field(win, id, x, y, w, label, text)
    fake.texts[#fake.texts + 1] = "[field] " .. label .. "=" .. tostring(text)
    return fake.id_text or text, y + 46, false
end
local ui_mock = { new = function(spec) fake.tabs = spec.tabs; fake.menu = setmetatable(fake, Menu); return fake.menu end }

local win = {
    render_text = function(_, _, _, _, text) fake.texts[#fake.texts + 1] = text end,
    render_line = function() end,
}

local vec2 = { new = function(x, y) return { x = x, y = y } end }
local movement = setmetatable({}, { __index = function() return function() end end })
local izi = { now = function() return T end, me = function() return player end, on_update = function() end,
    spell = function(id) return { id = id, maximum_range = 30 } end, enemies = function() return {} end }
local MOCKS = {
    ui = ui_mock, ["common/izi_sdk"] = izi, ["common/utility/simple_movement"] = movement,
    ["common/utility/auto_attack_helper"] = { ATTACK_TYPE = {} },
    ["common/geometry/vector_2"] = vec2, ["common/geometry/vector_3"] = { new = function(x, y, z) return { x = x, y = y, z = z } end },
    ["common/enums"] = { window_enums = { font_id = { FONT_SMALL = 1 } }, power_type = { MANA = 0 } },
    ["common/color"] = { new = function(r, g, b, a) return { r, g, b, a } end },
    ["route_mara_princess"] = { name = "Mock", segments = {} },
}
local orig = require
require = function(n) if MOCKS[n] ~= nil then return MOCKS[n] end return orig(n) end

local K = require("constants")
local config = require("config")
local gui = require("gui")
local state = require("state")
local spellscan = require("spellscan")
local store = require("rotation_store")
local s = state.new()

-- Tab + widgets ---------------------------------------------------------------
check("Rotation tab registered last (saved tab positions unchanged)",
    fake.tabs[#fake.tabs].id == "rotation" and fake.tabs[#fake.tabs].label == "Rotation" and #fake.tabs == 9)
for _, id in ipairs({ "rot_enabled", "rot_loot", "rot_engage", "rot_search", "rot_aoe", "rot_mode_id", "rot_mode_all", "rot_mob_id" }) do
    local r = fake.elements[K.MENU_PREFIX .. id]
    check("widget " .. id .. " on Rotation tab", r and r.tab == "rotation")
end
check("mode + mob id widgets persisted but hidden (custom rows)",
    fake.elements[K.MENU_PREFIX .. "rot_mode_id"].skip_draw and fake.elements[K.MENU_PREFIX .. "rot_mob_id"].skip_draw)
check("config bound to the widgets", config.menu.rot_enabled ~= nil and config.menu.rot_mob_id ~= nil)
local has_status = false
for _, it in ipairs(fake.status) do if it.label == "Rotation" then has_status = true end end
check("status panel has a Rotation line", has_status)

-- Render before scan -----------------------------------------------------------
config.menu.show_window = el(true)
gui.draw(s, {})
local tabfn = fake.on_tabs["rotation"]
local function render()
    fake.rows, fake.texts = {}, {}
    local ok, h = pcall(tabfn, win, 0, 0, 500, 400, fake)
    return ok, h
end
local ok, h = render()
check("tab renders before the scan", ok, h)
local function has_text(pat)
    for _, t in ipairs(fake.texts) do if tostring(t):find(pat) then return true end end
    return false
end
check("shows 'Scanning spellbook' before the 5 s scan", has_text("Scanning spellbook"))

-- Scan, then render -----------------------------------------------------------
spellscan.tick(); T = T + 6; spellscan.tick()
ok, h = render()
check("tab renders after the scan", ok, h)
check("returns its height for scrolling", type(h) == "number" and h > 300, h)
local function has_row(pat)
    for _, l in ipairs(fake.rows) do if l:find(pat) then return true end end
    return false
end
check("BUFFS lists Frost Armor", has_row("^Frost Armor"))
check("DPS lists Fireball once", (function() local n = 0 for _, l in ipairs(fake.rows) do if l:find("^Fireball") then n = n + 1 end end return n == 1 end)())
check("DPS row shows role", has_row("^Fire Blast  %-  cooldown strike"))
check("RACIALS lists Blood Fury", has_row("^Blood Fury"))
check("section headers", has_text("^BUFFS") and has_text("^DPS SPELLS") and has_text("^RACIALS"))

-- Mutual exclusion through the drawn rows -------------------------------------
fake.click_label = "Set Target ID"; render(); fake.click_label = nil
check("click Set Target ID -> on", config.rot_mode() == config.ROT_MODE_ID)
render()
check("Mob ID field shown in Set Target ID mode", has_text("%[field%] Enemy Mob ID"))
fake.click_label = "Attack ALL Mobs"; render(); fake.click_label = nil
check("click Attack ALL -> on and Set Target ID off",
    config.rot_mode() == config.ROT_MODE_ALL and config.menu.rot_mode_id.v == false)
render()
check("Mob ID field hidden in Attack ALL mode", not has_text("%[field%]"))
fake.click_label = "Attack ALL Mobs"; render(); fake.click_label = nil
check("click Attack ALL again -> no mode", config.rot_mode() == config.ROT_MODE_NONE)

-- Spell toggle -> store ------------------------------------------------------------
fake.click_label = "Fireball  -  filler"; render(); fake.click_label = nil
check("Fireball checkbox toggles the store", store.is_on("dps", "Fireball"))

-- Set button -> flag -------------------------------------------------------------
config.set_rot_mode(config.ROT_MODE_ID)
fake.id_text = "4321"; fake.launch_click = "Set"; render(); fake.launch_click = nil
check("Set button raises flag with the typed id", s.flag_rot_set_mob == true and s.rot_mob_buf == "4321")

print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
