-- Loader end-to-end test against a mock GitHub.
-- Run:  luajit tests/test_loader.lua <project root>
local ROOT = arg[1] or "."
package.path = ROOT .. "/tests/?.lua;" .. package.path
local mock = require("mock_core")
mock.install(ROOT)
local check = mock.check

-- A fake product repo exercising what real Sylvanas plugins do.
local SHA = "0123456789abcdef0123456789abcdef01234567"
local REPO = {
    ["manifest.lua"] = [[return { files = {
        { path = "header.lua" }, { path = "main.lua" }, { path = "state.lua" },
        { path = "data/big.lua" }, { path = "../evil.lua" }, { path = "https://x/y.lua" } } }]],
    ["header.lua"] = [[
        local v = require("state")                     -- header may require modules
        local plugin = { name = "fake", load = true }
        if core.get_game_version() ~= "Tbc" then plugin.load = false end
        _G.FAKE_SESSION = (_G.FAKE_SESSION or 0) + 1   -- session counter like the Grindbot
        return plugin]],
    ["state.lua"] = [[return { name = "fake-state" }]],
    ["data/big.lua"] = [[return { rows = 3 }]],
    ["main.lua"] = [[
        package.loaded["state"] = nil                  -- hot-reload pattern from the Grindbot
        local st = require("state")
        local big = require("data/big")
        assert(package.preload["data/big"], "preload holds compiled chunks")
        package.preload["data/big"] = nil              -- release pattern from the Grindbot
        assert(require("data/big").rows == 3, "loaded cache survives preload release")
        local vec2 = require("common/geometry/vector_2") -- falls through to host require
        core.log("fake main ok " .. st.name .. " " .. MASTER_FARMER.version_id)
        core.register_on_render_callback(function() core.graphics.text_2d() end)
        core.register_on_render_window_callback(function() _G.FAKE_RW = (_G.FAKE_RW or 0) + 1 end)
        PRIVATE_GLOBAL = true                          -- implicit globals stay inside the product
        return { on_unload = function() core.log("fake unloaded") end }]],
}
local flaky = 0
local network_up = true
mock.http = function(url)
    if not network_up then return 0, "" end
    if url:find("api.github.com/repos/L333T/fake/commits/main", 1, true) then return 200, SHA .. "\n" end
    local file = url:match("raw.githubusercontent.com/L333T/fake/" .. SHA .. "/(.+)$")
    if file == "state.lua" and flaky < 2 then flaky = flaky + 1; return 503, "" end -- retried
    if file and REPO[file] then return 200, REPO[file] end
    return 404, ""
end

local loader = require("modules/loader")
local product = { id = "fake", repo = "L333T/fake" }

-- 1. memory-only load
loader.load(product, "tbc"); mock.pump()
local p = loader.get("fake")
check("product running", p.status == "running")
check("files pinned to the resolved commit", mock.requests[2]:find(SHA, 1, true) ~= nil)
check("unsafe manifest paths ignored", not table.concat(mock.requests, " "):find("evil", 1, true))
check("503 retried until success", flaky == 2)
check("header ran (session counter bumped)", _G.FAKE_SESSION == 1)
check("main ran with package/preload semantics", mock.has_log("fake main ok fake%-state tbc"))
check("source text dropped", p.files == nil)
local wrote = false
for k, v in pairs(mock.disk) do if k:find("cache") and v ~= "" then wrote = true end end
check("nothing written to disk", not wrote)
mock.callbacks.render(); check("render callback dispatched", mock.text2d == 1)
loader.dispatch("render_window"); check("render_window routed", _G.FAKE_RW == 1)
check("implicit globals stay private to the product", rawget(_G, "PRIVATE_GLOBAL") == nil)

-- 2. unload
loader.unload("fake")
mock.callbacks.render(); check("unload removes callbacks", mock.text2d == 1)
check("on_unload called", mock.has_log("fake unloaded"))

-- 3. header gate refuses another client
mock.game_version = "Midnight"
loader.load(product, "retail"); mock.pump()
p = loader.get("fake")
check("header load=false -> error", p.status == "error" and p.note:find("load check") ~= nil)
mock.game_version = "Tbc"

-- 4. no offline copy exists any more: network down is a clean error
network_up = false
loader.load(product, "tbc"); mock.pump()
check("network down -> clean error (no disk fallback)", loader.get("fake").status == "error")
network_up = true

-- 5. a copy left by an older launcher is wiped, and nothing new is written
mock.disk["master_farmer/cache/fake/_index.txt"] = "main.lua"
mock.disk["master_farmer/cache/fake/main.lua"] = "return 1"
loader.load(product, "tbc"); mock.pump()
check("old offline copy wiped on load", mock.disk["master_farmer/cache/fake/main.lua"] == ""
    and mock.disk["master_farmer/cache/fake/_index.txt"] == "")
local leftover = false
for k, v in pairs(mock.disk) do if k:find("cache") and v ~= "" then leftover = true end end
check("still nothing written to disk", not leftover)
loader.unload("fake")

-- 6. missing repo
network_up = true
loader.load({ id = "nope", repo = "L333T/nope" }, "tbc"); mock.pump()
p = loader.get("nope")
check("missing repo -> HTTP 404 error", p.status == "error" and p.note:find("404") ~= nil)

mock.finish()
