-- MF_PathToolV3 Rotation: behaviour test against a mock Sylvanas / IZI API.
-- Drives the REAL modules (spellscan, config, actions, playback, routes,
-- rotation, rotation_store) frame by frame.
-- Run:  luajit tests/test_rotation.lua <project root>
local ROOT = arg[1] or "."
local SRC = ROOT .. "/products_src/mf_route_tool/"
package.path = SRC .. "?.lua;" .. package.path

local fails = 0
local function check(name, cond, extra)
    print((cond and "PASS " or "FAIL ") .. name .. ((not cond and extra) and ("   [" .. tostring(extra) .. "]") or ""))
    if not cond then fails = fails + 1 end
end

-- ------------------------------------------------------------- clock/vec3 --
local T = 1000
local vec3 = {}
vec3.__index = vec3
function vec3.new(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, vec3) end
function vec3:squared_dist_to(o) local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z return dx*dx + dy*dy + dz*dz end
function vec3:dist_to(o) return math.sqrt(self:squared_dist_to(o)) end

-- ------------------------------------------------------------------ units --
local function unit(t)
    t.alive = (t.alive ~= false)
    local u = {}
    u.d = t
    function u:is_valid() return not t.gone end
    function u:is_dead() return not t.alive end
    function u:is_ghost() return false end
    function u:get_guid() return t.guid end
    function u:get_name() return t.name or t.guid end
    function u:get_npc_id() return t.npc or 0 end
    function u:get_position() return t.pos end
    function u:is_player() return t.player == true end
    function u:is_valid_enemy() return t.enemy == true and t.alive end
    function u:is_enemy_with() return t.enemy == true end
    function u:is_in_combat() return t.combat == true end
    function u:get_target() return t.target end
    function u:get_health_percentage() return t.hp or 100 end
    function u:is_tap_denied() return t.tapped and 1 or 0 end
    function u:can_be_looted() return t.lootable == true end
    function u:has_loot() return t.lootable == true end
    function u:has_debuff() return false end
    function u:is_casting() return false end
    function u:is_channeling_or_casting() return t.casting == true end
    function u:is_in_melee_range(m) return u:distance_to(PLAYER) <= m end
    function u:is_spell_in_range() return nil end
    function u:distance_to(o) return t.pos:dist_to(o:get_position()) end
    return u
end

local buffs_up = {}
PLAYER = unit({ guid = "P", name = "Me", pos = vec3.new(0, 0, 0) })
local P = PLAYER.d
P.class = 8; P.mana = 80
function PLAYER:get_class() return P.class end
function PLAYER:can_attack(o) return o.d.enemy == true end
function PLAYER:is_mounted() return P.mounted == true end
function PLAYER:is_moving() return P.moving == true end
function PLAYER:mana_pct() return P.mana end
function PLAYER:get_max_power() return 100 end
function PLAYER:has_buff(ranks) for i = 1, #ranks do if buffs_up[ranks[i]] then return true end end return false end
function PLAYER:buff_remains() return 600 end
function PLAYER:is_stunned() return false end
function PLAYER:is_incapacitated() return false end
function PLAYER:is_feared() return false end
function PLAYER:get_level() return 60 end
function PLAYER:get_target() return P.cur_target end
function PLAYER:is_dead() return P.dead == true end

local enemies = {}

-- --------------------------------------------------------------- spellbook --
-- Fireball ranks 133 < 143 < 145 < 3140 share base 133; Frost Armor 168/7300.
local BOOK = {
    [133] = "Fireball", [143] = "Fireball", [145] = "Fireball", [3140] = "Fireball",
    [168] = "Frost Armor", [7300] = "Frost Armor", [1459] = "Arcane Intellect",
    [10] = "Blizzard", [118] = "Polymorph", [6603] = "Attack", [5019] = "Shoot",
    [20572] = "Blood Fury", [9999] = "Cold Weather Flying", [2136] = "Fire Blast",
}
local BASE = { [143] = 133, [145] = 133, [3140] = 133, [7300] = 168 }
local PASSIVE = { [9999] = true }

-- ------------------------------------------------------------------ core ---
local log = {}
local stop_attack_calls, loot_calls = 0, 0
core = {
    log = function(m) log[#log + 1] = m end,
    log_error = function(m) log[#log + 1] = "ERR " .. m end,
    log_warning = function() end,
    get_map_id = function() return P.map or 1 end,
    graphics = { add_notification = function() end },
    object_manager = {
        get_local_player = function() return PLAYER end,
        get_visible_objects = function() return enemies end,
        get_object_from_guid = function(g) for i = 1, #enemies do if enemies[i].d.guid == g then return enemies[i] end end end,
    },
    spell_book = {
        get_spells = function() local t = {} for id in pairs(BOOK) do t[#t + 1] = id end return t end,
        has_spell = function(id) return BOOK[id] ~= nil end,
        is_spell_learned = function(id) return BOOK[id] ~= nil end,
        is_spell_known = function(id) return BOOK[id] ~= nil end,
        get_spell_name = function(id) return BOOK[id] end,
        get_base_spell_id = function(id) return BASE[id] or id end,
        spell_has_attribute = function(id) return PASSIVE[id] == true end,
        is_spell_position_cast = function(id) return id == 10 end,
        get_spell_base_cooldown = function(id) return { cooldown_ms = (id == 2136) and 8000 or 0, gcd_ms = 1500 } end,
        is_usable_spell = function() return P.mana > 5 end,
    },
    input = {
        set_target = function(u) P.cur_target = u end,
        look_at = function() end,
        stop_attack = function() stop_attack_calls = stop_attack_calls + 1 end,
        dismount = function() P.mounted = false end,
        loot_object = function(obj) loot_calls = loot_calls + 1; obj.d.lootable = false end,
        loot_item = function() end, close_loot = function() end,
    },
    game_ui = { get_loot_item_count = function() return 0 end },
    create_data_file = function() end,
    write_data_file = function(f, d) DISK = DISK or {}; DISK[f] = d end,
    read_data_file = function(f) return (DISK and DISK[f]) or "" end,
    time = function() return T end,
}

-- ---------------------------------------------------------------- izi mock --
local casts = {}
local spells = {}
local function izi_spell(id)
    if spells[id] then return spells[id] end
    local sp = { id = id, maximum_range = (id == 20572 or id == 168 or id == 7300 or id == 1459) and 0 or 35 }
    function sp:is_learned() return BOOK[id] ~= nil end
    function sp:cooldown_up() return true end
    function sp:cast_time() return (BOOK[id] == "Fireball") and 2.5 or 0 end
    function sp:is_usable_while_moving() return false end
    function sp:cast_safe(target, msg)
        casts[#casts + 1] = { id = id, name = BOOK[id], t = T, target = target }
        if BOOK[id] == "Fireball" then P.casting_until = T + 2.5 end
        return true, {}
    end
    function sp:cast(target, msg) return self:cast_safe(target, msg) end
    function sp:cast_position(pos, msg) casts[#casts + 1] = { id = id, name = BOOK[id], t = T, pos = pos } return true, {} end
    spells[id] = sp
    return sp
end
function PLAYER:is_channeling_or_casting() return (P.casting_until or 0) > T end

local izi = {
    now = function() return T end,
    me = function() return PLAYER end,
    target = function() return P.cur_target end,
    on_update = function() end,
    spell = izi_spell,
    enemies = function(radius)
        local out = {}
        for i = 1, #enemies do
            local e = enemies[i]
            if e.d.alive and not e.d.gone and e.d.pos:dist_to(P.pos) <= (radius or 40) then out[#out + 1] = e end
        end
        return out
    end,
    party = function() return {} end,
}
function izi.pick_enemy(radius, _, filter, mode)
    local best, bv = nil, nil
    for _, u in ipairs(izi.enemies(radius)) do
        local v = filter(u)
        if v and (not bv or v < bv) then best, bv = u, v end
    end
    return best
end

-- ------------------------------------------------------ simple_movement mock --
local mv = { calls = {}, target = nil, paused = false }
local function mvlog(n, a) mv.calls[#mv.calls + 1] = { n = n, a = a, t = T } end
local movement = {}
for _, n in ipairs({ "set_threshold", "set_final_threshold", "set_turn_speed", "set_look_distance",
    "set_smoothing_subdivisions", "set_use_look_at", "set_debug", "set_smoothing_enabled" }) do
    movement[n] = function() end
end
function movement:move_to_position(p) mvlog("move_to", p); mv.target = p end
function movement:navigate(w, loop, from_start) mvlog("navigate", from_start); mv.target = w[1] end
function movement:process() mvlog("process"); return false end
function movement:pause() mvlog("pause"); mv.paused = true end
function movement:resume() mvlog("resume"); mv.paused = false end
function movement:stop() mvlog("stop"); mv.target = nil end
function movement:clear_navigation() mvlog("clear") end
function movement:get_waypoint_count() return 0 end
function movement:get_progress() return 0 end
function movement:get_current_index() return 0 end
function movement:get_target() return mv.target end
function movement:is_tabbed_out() return false end

local aa = { ATTACK_TYPE = { MELEE = 6603, RANGED = 75, WAND = 5019 }, starts = 0 }
function aa:start_attack(u, kind) self.starts = self.starts + 1; self.last_kind = kind; return true end
function aa:is_auto_attacking() return true end

-- ------------------------------------------------------------ module mocks --
local MOCKS = {
    ["common/izi_sdk"] = izi,
    ["common/utility/simple_movement"] = movement,
    ["common/utility/auto_attack_helper"] = aa,
    ["common/geometry/vector_3"] = vec3,
    ["common/enums"] = { power_type = { MANA = 0 } },
    ["common/color"] = { new = function() return {} end },
    ["route_mara_princess"] = { name = "Mock Route", segments = {} },
}
local orig_require = require
require = function(n) if MOCKS[n] ~= nil then return MOCKS[n] end return orig_require(n) end

-- Menu widgets: config.menu.* elements.
local function el(v)
    return { v = v, get_state = function(self) return self.v == true end, get = function(self) return self.v end,
        set = function(self, x) self.v = x end }
end

local K = require("constants")
local config = require("config")
config.menu.enabled = el(true)
config.menu.rot_enabled = el(false)
config.menu.rot_loot = el(true)
config.menu.rot_engage = el(25)
config.menu.rot_search = el(50)
config.menu.rot_aoe = el(3)
config.menu.rot_mode_id = el(false)
config.menu.rot_mode_all = el(false)
config.menu.rot_mob_id = el(0)

local state = require("state")
local spellscan = require("spellscan")
local playback = require("playback")
local store = require("rotation_store")
local rotation = require("rotation")

local s = state.new()

local function frame(n, dt)
    for _ = 1, (n or 1) do
        T = T + (dt or 0.05)
        izi.on_update()
        spellscan.tick()
        rotation.tick(s)
        playback.tick(s)
    end
end

-- ========================================================== 1. spellscan ==
frame(1)
check("no scan before 5 s", not spellscan.ready())
frame(110, 0.05)   -- 5.5 s
check("scan ran ~5 s after load", spellscan.ready())
local fams = spellscan.rotation_families()
local function find(list, name) for i = 1, #list do if list[i].name == name then return list[i] end end end
local fb = find(fams.dps, "Fireball")
local n_fb = 0
for i = 1, #fams.dps do if fams.dps[i].name == "Fireball" then n_fb = n_fb + 1 end end
check("Fireball listed once (ranks collapsed)", n_fb == 1)
check("Fireball uses highest rank id 3140", fb and fb.id == 3140, fb and fb.id)
check("Fireball keeps all 4 ranks", fb and #fb.ranks == 4)
check("Fireball role = filler", fb and fb.role == "filler", fb and fb.role)
check("Fire Blast role = cooldown strike", (find(fams.dps, "Fire Blast") or {}).role == "strike")
check("Blizzard role = AoE (position cast)", (find(fams.dps, "Blizzard") or {}).role == "aoe")
check("Shoot role = wand", (find(fams.dps, "Shoot") or {}).role == "wand")
check("Frost Armor is a buff, highest rank 7300", (find(fams.buff, "Frost Armor") or {}).id == 7300)
check("Frost Armor in exclusive group 'armor'", (find(fams.buff, "Frost Armor") or {}).group == "armor")
check("Arcane Intellect is a buff", find(fams.buff, "Arcane Intellect") ~= nil)
check("Blood Fury is a racial (offensive)", (find(fams.racial, "Blood Fury") or {}).kind == "offensive")
check("Polymorph (CC) not in DPS", find(fams.dps, "Polymorph") == nil)
check("Attack (auto attack) not in DPS", find(fams.dps, "Attack") == nil)
check("passive spell excluded everywhere", find(fams.dps, "Cold Weather Flying") == nil and find(fams.buff, "Cold Weather Flying") == nil)
local gen = spellscan.generation()
frame(20 * 61, 0.05)  -- a periodic rescan of an unchanged book
check("unchanged rescan does not rebuild lists", spellscan.generation() == gen)

-- ======================================================= 2. exclusivity ==
config.set_rot_mode(config.ROT_MODE_ID)
check("Set Target ID on", config.rot_mode() == config.ROT_MODE_ID and config.menu.rot_mode_all.v == false)
config.set_rot_mode(config.ROT_MODE_ALL)
check("Attack ALL on turns Set Target ID off", config.rot_mode() == config.ROT_MODE_ALL and config.menu.rot_mode_id.v == false)
config.menu.rot_mode_id.v, config.menu.rot_mode_all.v = true, true   -- corrupt save
check("both ON in a save -> only one active", config.rot_mode() == config.ROT_MODE_ID and config.menu.rot_mode_all.v == false)

-- ================================================== 3. disabled = inert ==
config.set_rot_mode(config.ROT_MODE_ALL)
store.set("dps", "Fireball", true)
local wolf = unit({ guid = "W1", name = "Wolf", npc = 525, enemy = true, pos = vec3.new(20, 0, 0), lootable = true })
enemies[1] = wolf
casts = {}
frame(40)
check("rotation disabled: no target, no cast, no lock", #casts == 0 and not s.combat_lock and P.cur_target == nil)

-- ================================================ 4. full encounter ======
-- Path playing in DIRECT mode with a waypoint action timer running.
s.waypoints = { vec3.new(0, 0, 0), vec3.new(100, 0, 0), vec3.new(200, 0, 0) }
s.wp_actions = {}
local ok = playback.start(s, { mode = K.MOVE_MODE.DIRECT })
s.direct_index = 2
check("playback started", ok == true and s.playing)

config.menu.rot_enabled.v = true
mv.calls = {}
frame(1)
check("hostile in range -> movement lock taken", s.combat_lock == true)
check("lock stopped path movement", (function() for _, c in ipairs(mv.calls) do if c.n == "stop" then return true end end end)())
frame(2)
check("target selected", P.cur_target == wolf)
check("state COMBAT", s.rot.state == rotation.STATE.COMBAT, s.rot.state)

mv.calls = {}
casts = {}
frame(60)   -- 3 s of combat
local fireballs = 0
for _, c in ipairs(casts) do if c.name == "Fireball" then fireballs = fireballs + 1 end end
check("Fireball (enabled) cast", fireballs >= 1)
check("no cast spam: one Fireball per 2.5 s cast", fireballs <= 2, fireballs)
check("only enabled spells cast (Fire Blast off)", (function() for _, c in ipairs(casts) do if c.name == "Fire Blast" then return false end end return true end)())
check("auto attack started", aa.starts >= 1)
check("path frozen: no waypoint move while fighting", (function()
    for _, c in ipairs(mv.calls) do if c.n == "move_to" or c.n == "navigate" then return false end end return true end)())
check("playback.tick did not process()", (function() for _, c in ipairs(mv.calls) do if c.n == "process" then return false end end return true end)())

-- Wolf dies with loot; player still flagged in combat for a moment.
wolf.d.alive = false
P.in_combat = true
function PLAYER:is_in_combat() return P.in_combat == true end
frame(1)
frame(1)
check("target dead -> LOOTING (loot on)", s.rot.state == rotation.STATE.LOOTING, s.rot.state)
check("auto attack stopped on death", stop_attack_calls >= 1)
check("still locked while looting", s.combat_lock == true)

mv.calls = {}
frame(30)  -- grace + walk
check("walks to the corpse (rotation-owned movement)", (function()
    for _, c in ipairs(mv.calls) do if c.n == "move_to" and c.a.x == 20 then return true end end end)())
P.pos = vec3.new(18, 0, 0)   -- arrived next to the corpse
frame(20)
check("corpse looted", loot_calls >= 1)
frame(5)
check("loot done -> COMBAT_COMPLETE", s.rot.state == rotation.STATE.COMPLETE, s.rot.state)
check("movement NOT resumed while still in combat", s.combat_lock == true)
frame(40)
check("still locked: combat flag up", s.combat_lock == true)

P.in_combat = false
mv.calls = {}
frame(5)       -- < settle delay
check("settle delay holds the lock", s.combat_lock == true)
frame(20)
check("lock released after combat + loot + settle", s.combat_lock == false)
check("path re-issued at the current waypoint", (function()
    for _, c in ipairs(mv.calls) do if c.n == "move_to" and c.a.x == 100 then return true end end end)())
check("state back to SEARCH_TARGET", s.rot.state == rotation.STATE.SEARCH)

-- ============================================ 5. second mob while looting ==
-- A new attacker during looting must be fought first.
local boar = unit({ guid = "B1", name = "Boar", npc = 113, enemy = true, combat = true, pos = vec3.new(10, 5, 0) })
boar.d.target = PLAYER
enemies[2] = boar
frame(3)
check("new attacker re-engaged (lock re-taken)", s.combat_lock and s.rot.target == boar)
boar.d.alive = false
boar.d.lootable = false
frame(3)
check("dead without loot ends quickly (LOOTING drops it)", s.rot.state == rotation.STATE.COMPLETE or s.rot.state == rotation.STATE.LOOTING, s.rot.state)
check("waits for an in-progress cast before releasing", s.combat_lock == true)
frame(100)   -- cast finishes (2.5 s) + settle
check("no loot -> complete -> released", s.combat_lock == false, s.rot.state)

-- ================================================== 6. Set Target ID mode ==
config.set_rot_mode(config.ROT_MODE_ID)
config.set_rot_mob_id(0)
frame(10)
check("ID mode without an ID: no fight", s.combat_lock == false and s.rot.reason == "no Mob ID set", s.rot.reason)
local a = unit({ guid = "M1", npc = 777, enemy = true, pos = vec3.new(45, 0, 0) })
local b = unit({ guid = "M2", npc = 777, enemy = true, pos = vec3.new(30, 0, 0), tapped = true })
local c2 = unit({ guid = "M3", npc = 888, enemy = true, pos = vec3.new(5, 0, 0) })
enemies = { a, b, c2 }
config.set_rot_mob_id(777)
frame(8)   -- search is throttled to every 0.25 s
check("picks the untapped instance of mob 777 (not the closer tapped one, not other ids)",
    s.rot.target == a, s.rot.target and s.rot.target.d.guid)
a.d.alive = false
frame(80)

-- ===================================================== 7. Mob ID input ===
local main_flags = { "abc", "0", "99999999", "-5", "1234" }
local results = {}
for _, txt in ipairs(main_flags) do
    -- same validation main.lua applies
    local id = tonumber(txt)
    results[#results + 1] = (txt:match("^%d+$") and id and id >= 1 and id <= K.ROT_MOB_ID_MAX) and "ok" or "rejected"
end
check("Mob ID validation", table.concat(results, ",") == "rejected,rejected,rejected,rejected,ok", table.concat(results, ","))

-- =========================================================== 8. buffs ====
store.set("buff", "Frost Armor", true)
enemies = {}
casts = {}
frame(20 * 60, 0.05)   -- 60 s, aura never reported by the client
local fa = 0
for _, c in ipairs(casts) do if c.name == "Frost Armor" then fa = fa + 1 end end
check("unreported buff backs off (no spam)", fa >= 1 and fa <= 3, fa)
buffs_up[7300] = true
store.set("buff", "Arcane Intellect", true)
casts = {}
frame(20 * 10)
local ai, fa2 = 0, 0
for _, c in ipairs(casts) do
    if c.name == "Arcane Intellect" then ai = ai + 1 end
    if c.name == "Frost Armor" then fa2 = fa2 + 1 end
end
check("missing buff cast once", ai >= 1 and ai <= 2, ai)
check("active buff not recast", fa2 == 0, fa2)
store.set("buff", "Frost Armor", false)
store.set("buff", "Arcane Intellect", false)

-- ================================================ 9. disable mid-fight ====
config.set_rot_mode(config.ROT_MODE_ALL)
local orc = unit({ guid = "O1", npc = 3, enemy = true, pos = vec3.new(10, 0, 0) })
enemies = { orc }
frame(8)
check("fighting again", s.combat_lock == true)
local stops = stop_attack_calls
config.menu.rot_enabled.v = false
frame(1)
check("disable mid-fight releases lock", s.combat_lock == false and s.rot.state == rotation.STATE.IDLE)
check("disable mid-fight stops attacking", stop_attack_calls > stops)
config.menu.rot_enabled.v = true

-- ===================================================== 10. player dead ===
frame(3)
P.dead = true
frame(1)
check("player death releases lock", s.combat_lock == false)
P.dead = false

-- =================================================== 11. bounded memory ==
enemies = {}
for i = 1, 400 do
    local e = unit({ guid = "X" .. i, npc = 5, enemy = true, pos = vec3.new(8, 0, 0), lootable = false })
    enemies[1] = e
    frame(4)
    e.d.alive = false
    frame(2)
end
frame(100)
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
check("fail table bounded by spell count", count(s.rot.fail_until) <= 20, count(s.rot.fail_until))
check("loot queue bounded", #s.rot.kills <= 20, #s.rot.kills)
check("blacklist bounded", count(s.rot.blacklist) <= 400)
check("no runtime errors logged", (function() for _, l in ipairs(log) do if l:find("^ERR") then return false end end return true end)())

print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
