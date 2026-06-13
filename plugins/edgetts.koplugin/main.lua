local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local TouchMenu = require("ui/widget/touchmenu")
local logger = require("logger")
local _ = require("gettext")
local TTSController = require("tts_controller")
local EdgeProvider = require("edge_provider")
local SystemProvider = require("system_provider")
local DataStorage = require("datastorage")

local EdgeTTS = WidgetContainer:extend{
    name = "edgetts",
    is_doc_only = false,
    controller = nil,
    providers = {},
    current_provider = "edge",
    settings = {
        provider = "edge",
        voice = "vi-VN-HoaiMyNeural",
        rate = "+0%",
        api_url = "https://tts.ngtri.io.vn/tts",
        continuous_reading = true,
    },
}

function EdgeTTS:_getProviders()
    return self.providers
end

function EdgeTTS:init()
    local android_ok, _ = pcall(require, "android")

    local edge = EdgeProvider:new{
        api_url = self.settings.api_url,
        voice = self.settings.voice,
        rate = self.settings.rate,
        output_dir = DataStorage:getDataDir() .. "/edge_tts_cache/",
    }
    edge._android_play = function(path)
        if android_ok then
            return require("android").playAudio(path)
        end
        return false
    end
    edge._android_stop = function()
        if android_ok then
            require("android").stopAudio()
        end
    end
    self.providers.edge = edge

    if android_ok then
        self.providers.system = SystemProvider:new()
    end

    self.controller = TTSController:new()
    self.controller:setUI(self.ui)
    self.controller:setProvider(self.providers[self.current_provider] or edge)

    self.ui.menu:registerToMainMenu(self)
end

function EdgeTTS:addToMainMenu(menu_items)
    menu_items.edgetts = {
        text = _("Edge TTS"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text_func = function()
                    if self.controller and self.controller.is_reading then
                        if self.controller.is_paused then
                            return "▶ " .. _("Resume Reading")
                        else
                            return "⏸ " .. _("Pause Reading")
                        end
                    end
                    return "▶ " .. _("Start Reading")
                end,
                callback = function()
                    if not self.controller then return end
                    if self.controller.is_reading then
                        self.controller:pause()
                    else
                        self.controller:start()
                    end
                end,
            },
            {
                text = _("Stop Reading"),
                enabled_func = function()
                    return self.controller and self.controller.is_reading
                end,
                callback = function()
                    if self.controller then
                        self.controller:stop()
                    end
                end,
            },
            {
                text = _("Settings"),
                callback = function()
                    if self.controller then self.controller:stop() end
                    self:_showSettings()
                end,
            },
            {
                text_func = function()
                    local name = self.current_provider == "edge" and "Edge TTS" or "System TTS"
                    return _("Provider: ") .. name
                end,
                callback = function()
                    self:_switchProvider()
                end,
            },
        },
    }
end

function EdgeTTS:_switchProvider()
    local options = {}
    if self.providers.edge then table.insert(options, "Edge TTS") end
    if self.providers.system then table.insert(options, "System TTS") end

    if #options == 0 then
        UIManager:show(InfoMessage:new{ text = _("No TTS providers available") })
        return
    end

    local current_idx = self.current_provider == "edge" and 1 or 2
    local next_idx = (current_idx % #options) + 1
    local next_name = options[next_idx]
    local next_key = next_name == "Edge TTS" and "edge" or "system"

    self.current_provider = next_key
    self.controller:setProvider(self.providers[next_key])

    UIManager:show(InfoMessage:new{
        text = _("TTS provider switched to: ") .. next_name,
    })
end

function EdgeTTS:_showSettings()
    local settings_items = {
        {
            text = _("Voice: ") .. self.settings.voice,
            callback = function()
                if self.settings.voice:match("HoaiMy") then
                    self.settings.voice = "vi-VN-NamMinhNeural"
                else
                    self.settings.voice = "vi-VN-HoaiMyNeural"
                end
                if self.providers.edge then
                    self.providers.edge.voice = self.settings.voice
                end
            end,
        },
        {
            text = _("Continuous reading: ") .. (self.settings.continuous_reading and "ON" or "OFF"),
            callback = function()
                self.settings.continuous_reading = not self.settings.continuous_reading
            end,
        },
    }

    UIManager:show(TouchMenu:new{
        title = _("TTS Settings"),
        item_table = settings_items,
    })
end

return EdgeTTS
