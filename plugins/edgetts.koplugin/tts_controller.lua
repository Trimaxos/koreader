local Event = require("ui/event")
local logger = require("logger")
local Screen = require("device").screen

local TTSController = {
    is_reading = false,
    is_paused = false,
    provider = nil,
    ui = nil,
    current_text = "",
}

function TTSController:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function TTSController:setUI(ui)
    self.ui = ui
end

function TTSController:setProvider(provider)
    self.provider = provider
end

function TTSController:_getPageText(document)
    if not document then return "" end
    if self.ui and self.ui.rolling then
        local res = document:getTextFromPositions(
            {x = 0, y = 0},
            {x = Screen:getWidth(), y = Screen:getHeight()},
            true
        )
        if res and res.text then
            return res.text
        end
    else
        local page = self.ui and self.ui:getCurrentPage() or 1
        local boxes = document:getTextBoxes(page)
        if boxes then
            local lines = {}
            for _, line in ipairs(boxes) do
                for _, word in ipairs(line) do
                    table.insert(lines, word.word)
                end
            end
            return table.concat(lines, " ")
        end
    end
    return ""
end

function TTSController:start()
    if not self.provider or not self.ui then return end
    self.is_reading = true
    self.is_paused = false
    self:_readCurrentPage()
end

function TTSController:_readCurrentPage()
    if not self.is_reading or self.is_paused then return end

    local text = self:_getPageText(self.ui.document)
    self.current_text = text

    if not text or text == "" then
        self:_nextPage()
        return
    end

    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        self:_nextPage()
        return
    end

    self.provider:speak(text,
        function()
            logger.dbg("TTS: Page finished, advancing to next page")
            self:_nextPage()
        end,
        function(err)
            logger.warn("TTS Error: " .. tostring(err))
            self:stop()
        end
    )
end

function TTSController:_nextPage()
    if not self.is_reading or self.is_paused then return end
    if self.ui then
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
        local UIManager = require("ui/uimanager")
        UIManager:scheduleIn(0.3, function()
            self:_readCurrentPage()
        end)
    end
end

function TTSController:pause()
    if self.is_reading then
        if self.is_paused then
            self.is_paused = false
            self:_readCurrentPage()
        else
            self.is_paused = true
            if self.provider then
                self.provider:stop()
            end
        end
    end
end

function TTSController:stop()
    self.is_reading = false
    self.is_paused = false
    if self.provider then
        self.provider:stop()
    end
end

return TTSController
