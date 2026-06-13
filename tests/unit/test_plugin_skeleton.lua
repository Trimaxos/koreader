--- Tests for EdgeTTS plugin skeleton (main.lua)
describe("EdgeTTS Plugin Skeleton", function()
    it("should load _meta.lua without errors", function()
        local meta = dofile("plugins/edgetts.koplugin/_meta.lua")
        check.not_nil(meta, "_meta should return a table")
        check.not_nil(meta.title, "_meta needs a title")
        check.not_nil(meta.description, "_meta needs a description")
        check.not_nil(meta.version, "_meta needs a version")
    end)

    it("should load main.lua without errors", function()
        local plugin = dofile("plugins/edgetts.koplugin/main.lua")
        check.not_nil(plugin, "plugin should be a table")
        check.not_nil(plugin.init, "plugin needs an init method")
        check.not_nil(plugin.addToMainMenu, "plugin needs addToMainMenu")
    end)

    it("should register menu items", function()
        local plugin = dofile("plugins/edgetts.koplugin/main.lua")
        local menu_items = {}
        plugin:addToMainMenu(menu_items)
        check.not_nil(menu_items.edgetts, "should register 'edgetts' in menu")
        local item = menu_items.edgetts
        check.not_nil(item.text, "menu item needs text")
        check.not_nil(item.sub_item_table, "should have submenu")
        check.ok(#item.sub_item_table >= 2, "should have at least Play and Stop")
    end)

    it("should list available providers after init", function()
        local plugin = dofile("plugins/edgetts.koplugin/main.lua")
        -- Call init with a mock UI so providers get populated
        plugin.ui = {
            document = nil,
            menu = { registerToMainMenu = function() end },
            registerPostInitCallback = function() end,
            rolling = true,
        }
        plugin:init()
        local providers = plugin:_getProviders()
        check.not_nil(providers, "providers table should exist")
        check.not_nil(providers.edge, "edge provider should exist after init")
    end)
end)
