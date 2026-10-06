-- Draws every launcher screen / tab / modal / card state against a mock window
-- and fails on any runtime error.  Run:  luajit tests/test_gui.lua <project root>
local ROOT = arg[1] or "."
package.path = ROOT .. "/tests/?.lua;" .. package.path
local mock = require("mock_core")
mock.install(ROOT)
mock.data_root = nil            -- a fresh PC: no cached artwork on disk
local check = mock.check

-- The assets repo: serve the real PNGs for raw.githubusercontent URLs.
local ASSET_URL = "https://raw.githubusercontent.com/L333T/master-farmer-assets/main/gui/"
local assets_online = false
local asset_requests = 0
mock.http = function(url)
    local name = url:sub(1, #ASSET_URL) == ASSET_URL and url:sub(#ASSET_URL + 1)
    if not name then return 404, "" end
    asset_requests = asset_requests + 1
    if not assets_online then return 0, "" end
    local f = io.open(ROOT .. "/repos/master-farmer-assets/gui/" .. name, "rb")
    if not f then return 404, "" end
    local d = f:read("*a"); f:close()
    return 200, d
end

local click_all = false
local click_at = nil            -- {x, y} window-local point to click, or nil
local texts = {}
local win_mt = { __index = function(_, k)
    if k == "get_position" then return function() return { x = 100, y = 50 } end end
    if k == "is_rect_clicked" then return function(_, mn, mx)
        if click_at then return click_at[1] >= mn.x and click_at[1] <= mx.x and click_at[2] >= mn.y and click_at[2] <= mx.y end
        return click_all
    end end
    if k == "is_mouse_hovering_rect" then return function() return true end end
    if k == "begin" then return function(_, ...) local a = { ... }; a[#a](); return true end end
    if k == "render_text_custom_size" then return function(_, _, _, _, _, t) texts[#texts + 1] = t end end
    return function() end
end }
core.menu = { window = function() return setmetatable({}, win_mt) end }
local function shown(pat)
    for _, t in ipairs(texts) do if tostring(t):find(pat) then return true end end
    return false
end

-- ---------------------------------------------------------- artwork gate --
dofile(ROOT .. "/plugin/Master_Farmer/main.lua")
check("startup prefetches all 5 artwork files", #mock.pending == 5, #mock.pending)
texts = {}
mock.callbacks.render_window()
check("window shows 'Loading artwork' while downloading", shown("Loading artwork from GitHub"))
mock.pump(3)                     -- downloads fail (offline)
texts = {}
mock.callbacks.render_window()
check("failed download shows retry message", shown("Could not download the launcher artwork"))

local textures = require("modules/textures")
assets_online = true
textures.retry()
mock.callbacks.render_window()   -- a retry takes effect on the next draw
mock.pump(3)
texts = {}
mock.logs = {}
mock.callbacks.render_window()
check("after retry the artwork is ready", textures.status("main_bg.png") == "ready")
check("launcher draws the real screen", shown("Recently") or shown("Nothing yet") or shown("Tbc"))
check("downloaded artwork cached in versioned folder",
    (mock.disk["master_farmer/gui_v1/main_bg.png"] or "") ~= "")
check("no errors once online", not mock.has_log("^ERR"))

local screens, config, loader, ui = require("modules/screens"), require("modules/config"),
    require("modules/loader"), require("modules/ui")
for _, n in ipairs(config.asset_files) do textures.get(n) end
mock.pump(3)

local win = core.menu.window()
local function draw(ctx)
    ui.begin_frame(win, 0.9, 0.5)
    local base = { status = "x", game_version = "Tbc", detected = "tbc", tab = "products" }
    return pcall(screens.draw, setmetatable(ctx, { __index = base }))
end

local ok, err = true, nil
local function run(ctx)
    local o, e = draw(ctx)
    if not o then ok, err = false, e end
end

for _, modal in ipairs({ false, "settings", "help" }) do run({ screen = "versions", modal = modal or nil }) end
for _, v in ipairs(config.versions) do
    if v.active then
        for _, tab in ipairs({ "products", "profiles", "settings", "help" }) do
            run({ screen = "products", version = v, tab = tab })
        end
    end
end
check("all screens, tabs and modals draw", ok); if err then print("  " .. err) end

-- Every card state, the Ameisen confirm modal (Ameisen not running), and Ameisen running
local states = { questing_grinding = "downloading", mf_route_tool = "running", sp_pull = "error" }
local real_get = loader.get
loader.get = function(id)
    local st = states[id]
    return st and { status = st, source = "cache", note = "HTTP 404 for main.lua", version_id = "tbc",
        progress = { done = 40, total = 129 } } or nil
end
ok, err = true, nil
local tbc = screens.find_version("tbc")
texts = {}
run({ screen = "products", version = tbc, tab = "products" })
check("TBC Utility card lists both tools",
    shown("^Path Recording & Rotation Tool$") and shown("^Slave Pens %- 4 Mage Pull Types$"))
check("each tool has its own state button", shown("^UNLOAD") and shown("RETRY"))
run({ screen = "products", version = tbc, tab = "profiles" })
run({ screen = "products", version = tbc, tab = "products",
    confirm = { product = config.find_product("questing_grinding"), version = tbc } })
_G.AmeisenNav = {}
run({ screen = "products", version = tbc, tab = "products" })
_G.AmeisenNav = nil
for _, sname in ipairs({ "idle", "downloading", "running", "error" }) do
    states = { mf_route_tool = sname, sp_pull = sname }
    run({ screen = "products", version = tbc, tab = "products" })
end
check("card states + Ameisen confirm draw", ok); if err then print("  " .. err) end
loader.get = real_get

-- Click each LOAD button of the two-product Utility card at its real position.
loader.load = function(p) LOADS = (LOADS or "") .. p.id .. "," end
local sc = 0.9   -- draw() passes the scale straight to ui.begin_frame
for _, by in ipairs({ 461, 547 }) do
    click_at = { 969 * sc, by * sc }
    run({ screen = "products", version = tbc, tab = "products" })
end
click_at = nil
check("Utility card row 1 LOAD -> Path Recording & Rotation Tool, row 2 -> Slave Pens",
    LOADS == "mf_route_tool,sp_pull,", LOADS)

-- Clicking everything in one frame must not error either
click_all = true
local loads = {}
loader.load = function(p) loads[#loads + 1] = p.id end
loader.unload, loader.clear_cache = function() end, function() end
ok, err = true, nil
for _, v in ipairs(config.versions) do
    if v.active then
        for _, tab in ipairs({ "products", "profiles", "settings", "help" }) do
            run({ screen = "products", version = v, tab = tab })
        end
    end
end
run({ screen = "versions" })
check("click-everything frames don't error", ok); if err then print("  " .. err) end

-- Settings: no GUI scale, no offline copy, no window reset - on either screen.
click_all = false
for _, ctx in ipairs({ { screen = "versions", modal = "settings" }, { screen = "products", version = tbc, tab = "settings" } }) do
    texts = {}
    run(ctx)
    check("Settings (" .. ctx.screen .. ") has no GUI scale / offline copy / reset",
        shown("SETTINGS") and not shown("GUI scale") and not shown("offline") and not shown("Reset window")
        and not shown("Clear plugin cache"))
end
check("fixed GUI scale 98%", config.gui_scale == 0.98)

-- Product availability per version
local function ids(vid)
    local t = {}
    for slot, list in pairs(config.products_for(vid)) do
        for _, p in ipairs(list) do t[#t + 1] = slot .. "=" .. p.id end
    end
    table.sort(t); return table.concat(t, " ")
end
check("forever: questing + path tool (utility)", ids("forever") == "1=questing_grinding 4=mf_route_tool", ids("forever"))
check("tbc: questing + both utility tools", ids("tbc") == "1=questing_grinding 4=mf_route_tool 4=sp_pull", ids("tbc"))
check("retail: path tool only", ids("retail") == "4=mf_route_tool")
check("classic: path tool only", ids("classic") == "4=mf_route_tool")
check("Route Maker / Combat Rotations cards now empty",
    config.products_for("tbc")[2] == nil and config.products_for("tbc")[3] == nil)
check("names", config.find_product("mf_route_tool").label == "Path Recording & Rotation Tool"
    and config.find_product("sp_pull").label == "Slave Pens - 4 Mage Pull Types")
check("Questing LOAD without Ameisen asks first (no direct load)", not (function()
    for _, id in ipairs(loads) do if id == "questing_grinding" then return true end end
end)())

-- Second start on the same PC: artwork comes from the cache, no download.
package.loaded["modules/textures"] = nil
local fresh = require("modules/textures")
local before = asset_requests
fresh.get("main_bg.png")
check("second start loads cached artwork without downloading",
    fresh.status("main_bg.png") == "ready" and asset_requests == before)

mock.finish()
