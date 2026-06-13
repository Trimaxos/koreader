local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local TouchMenu = require("ui/widget/touchmenu")
local logger = require("logger")
local _ = require("gettext")
local TTSController = require("tts_controller")
local EdgeProvider = require("edge_provider")
local DataStorage = require("datastorage")

local EdgeTTS = WidgetContainer:extend{
    name = "edgetts",
    is_doc_only = false,
    controller = nil,
    edge_provider = nil,
    settings = {
        voice = "vi-VN-HoaiMyNeural",
        rate = "+0%",
        api_url = "https://tts.ngtri.io.vn/tts",
        continuous_reading = true,
    },
}

function EdgeTTS:init()
    self.edge_provider = EdgeProvider:new{
        api_url = self.settings.api_url,
        voice = self.settings.voice,
        rate = self.settings.rate,
        output_dir = DataStorage:getDataDir() .. "/edge_tts_cache/",
    }

    self.controller = TTSController:new()
    self.controller:setUI(self.ui)
    self.controller:setProvider(self.edge_provider)

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
        },
    }
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
                if self.edge_provider then
                    self.edge_provider.voice = self.settings.voice
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
        title = _("Edge TTS Settings"),
        item_table = settings_items,
    })
end

return EdgeTTS
