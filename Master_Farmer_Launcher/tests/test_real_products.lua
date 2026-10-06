-- Runs the REAL products through the launcher's loader under LuaJIT:
--   mf_route_tool / sp_pull : served from the local build in repos/ (before push)
--   questing_grinding       : downloaded live from GitHub with curl
-- Verifies download, manifest, compile of every file and the header gate.
-- main.lua needs the real game API, so a "Startup error" from main is expected
-- here; anything earlier (HTTP, compile, header) is a real failure.
--
-- Run:  luajit tests/test_real_products.lua <project root> [--live]
--   --live  also serve mf-route-tool / sp-pull from GitHub instead of repos/
local ROOT = arg[1] or "."
local LIVE = arg[2] == "--live"
package.path = ROOT .. "/tests/?.lua;" .. package.path
local mock = require("mock_core")
mock.install(ROOT)
local check = mock.check

local function readf(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local d = f:read("*a"); f:close(); return d
end

local function curl(url, accept)
    local h = accept and (' -H "Accept: ' .. accept .. '"') or ""
    local f = io.popen('curl -s -L -A MasterFarmer' .. h .. ' -w "\\n%{http_code}" "' .. url .. '"')
    local out = f:read("*a"); f:close()
    local body, code = out:match("^(.*)\n(%d+)$")
    return tonumber(code) or 0, body or ""
end

local LOCAL = { ["L333T/mf-route-tool"] = "mf-route-tool", ["L333T/sp-pull"] = "sp-pull" }
mock.http = function(url)
    local repo = url:match("api%.github%.com/repos/([^/]+/[^/]+)/commits/")
    if repo and LOCAL[repo] and not LIVE then return 200, string.rep("a", 40) end
    if repo then return curl(url, "application/vnd.github.sha") end
    local r, file = url:match("raw%.githubusercontent%.com/([^/]+/[^/]+)/[^/]+/(.+)$")
    if LOCAL[r] and not LIVE then
        local body = readf(ROOT .. "/repos/" .. LOCAL[r] .. "/" .. file)
        return body and 200 or 404, body or ""
    end
    return curl(url)
end

-- What the products' headers touch
core.object_manager = { get_local_player = function()
    return { is_valid = function() return true end }
end }
core.get_exact_game_version = function() return "wow_tbc_us" end
core.http_post = function() end
mock.modules["common/izi_sdk"] = setmetatable({}, { __index = function() return function() end end })

local config = require("modules/config")
local loader = require("modules/loader")

for _, product in ipairs(config.products) do
    mock.logs = {}
    loader.load(product, "tbc")
    mock.pump(1200)   -- up to 120 simulated seconds
    local p = loader.get(product.id)
    local note = p.note or ""
    print(string.format("  %-18s status=%s  ref=%s  files=%s  note=%s", product.id, p.status, tostring(p.ref),
        p.progress and (p.progress.done .. "/" .. p.progress.total) or "-", note:sub(1, 140)))
    local got_to_main = p.status == "running" or note:find("^Startup error") ~= nil
    check(product.id .. ": downloaded, compiled, header passed", got_to_main)
end

mock.finish()
