#!/usr/bin/env luajit
---
-- Lightweight test runner for EdgeTTS plugin.
-- Doesn't need KOReader's C build — pure Lua unit tests.
--
-- Usage: luajit tests/run_tests.lua [test_name_pattern]
--

-- Minimal mock for KOReader dependencies that our code needs
local _G = _G
local test_results = { passed = 0, failed = 0, errors = {} }

-- Mock gettext
if not _G._ then
    _G._ = function(s) return s end
end

-- Mock gettext module for require("gettext")
local gettext_mock = { gettext = function(s) return s end }
setmetatable(gettext_mock, { __call = function(_, s) return s end })
package.preload["gettext"] = function() return gettext_mock end

-- Add plugin files to package.preload so require() works with forward-slashes
local plugin_root = "plugins/edgetts.koplugin/"
local function preload_plugin_module(name)
    local path = plugin_root .. name .. ".lua"
    local f, err = loadfile(path)
    if f then
        package.preload[name] = f
    end
end
package.path = package.path .. ";plugins/edgetts.koplugin/?.lua"

-- Mock logger
package.preload["logger"] = function()
    return {
        dbg = function(...) end,
        warn = function(...) print("[WARN]", ...) end,
        info = function(...) print("[INFO]", ...) end,
        err = function(...) print("[ERR]", ...) end,
        setLevel = function() end,
        levels = { warn = 2 },
    }
end

-- Mock DataStorage
package.preload["datastorage"] = function()
    return {
        getDataDir = function() return "/tmp/koreader-test" end,
        getHistoryDir = function() return "/tmp/koreader-test/history" end,
    }
end

-- Mock Screen
package.preload["device"] = function()
    local screen = {
        getWidth = function() return 1080 end,
        getHeight = function() return 1920 end,
    }
    return {
        screen = screen,
        input = {},
        model = "test-device",
    }
end

-- Mock UI modules
package.preload["ui/widget/container/widgetcontainer"] = function()
    return {
        extend = function(_, table)
            table = table or {}
            table.__index = table
            return table
        end
    }
end

package.preload["ui/widget/infomessage"] = function()
    return { new = function(_, o) return o end }
end

package.preload["ui/uimanager"] = function()
    return {
        show = function() end,
        scheduleIn = function() end,  -- no-op to prevent infinite loops in tests
    }
end

package.preload["ui/event"] = function()
    return {
        new = function(_, event_name, ...)
            return { name = event_name, args = {...} }
        end
    }
end

package.preload["ui/widget/confirmbox"] = function()
    return { new = function(_, o) return o end }
end

package.preload["ui/widget/touchmenu"] = function()
    return { new = function(_, o) return o end }
end

-- Mock http(s) for testing
package.preload["socket.http"] = function()
    return {}
end
package.preload["ssl.https"] = function()
    return {}
end
package.preload["ltn12"] = function()
    return {
        sink = {
            file = function(f) return function(chunk, err)
                if chunk then f:write(chunk) return 1
                else f:close() return 1 end
            end end,
            null = function() return function() return 1 end end,
            table = function(t) t = t or {}; return function(chunk) if chunk then table.insert(t, chunk) end; return 1 end, t end,
        },
        source = {
            string = function(s) return function() return s end end,
        },
        filter = {},
        pump = {},
    }
end
package.preload["socket"] = function()
    return {
        tcp = function() return {} end,
    }
end

-- Mock FFI utils  
package.preload["ffi/util"] = function()
    return {
        template = function(s, ...) return s end,
    }
end

-- Test helper functions
local function describe(name, fn)
    print("\n=== " .. name .. " ===")
    fn()
end

local function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        test_results.passed = test_results.passed + 1
        io.write("  ✅ " .. name .. "\n")
    else
        test_results.failed = test_results.failed + 1
        table.insert(test_results.errors, { name = name, err = err })
        io.write("  ❌ " .. name .. ": " .. tostring(err):match("[^\n]+") .. "\n")
    end
end

local check = {}
function check.ok(condition, msg)
    if not condition then
        error(msg or "assertion failed", 2)
    end
end

function check.equal(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected: " .. tostring(b) .. ", got: " .. tostring(a), 2)
    end
end

function check.is_true(v, msg)
    if v ~= true then
        error((msg or "") .. " expected true, got " .. tostring(v), 2)
    end
end

function check.not_nil(v, msg)
    if v == nil then
        error((msg or "") .. " expected non-nil", 2)
    end
end

_G.check = check

_G.describe = describe
_G.it = it

-- Now run the plugin tests
local pattern = arg and arg[1]

-- List of test modules to run
local test_modules = {
    "tests/unit/test_providers.lua",
    "tests/unit/test_controller.lua",
    "tests/unit/test_plugin_skeleton.lua",
}

for _, mod in ipairs(test_modules) do
    local ok, err = pcall(dofile, mod)
    if not ok then
        print("⚠️  Failed to load " .. mod .. ": " .. tostring(err))
    end
end

-- Summary
print(string.rep("=", 50))
print(string.format("Results: %d passed, %d failed, %d errors",
    test_results.passed, test_results.failed, #test_results.errors))

if test_results.failed > 0 then
    print("\nFailures:")
    for _, e in ipairs(test_results.errors) do
        print("  ❌ " .. e.name .. ": " .. tostring(e.err))
    end
    os.exit(1)
end
