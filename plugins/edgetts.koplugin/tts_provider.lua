--- Abstract TTS Provider interface
local TTSProvider = {}

function TTSProvider:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Speak the given text
-- @param text string to speak
-- @param on_complete function called when speech finishes
-- @param on_error function called on error (msg)
function TTSProvider:speak(text, on_complete, on_error)
    error("TTSProvider:speak() must be implemented")
end

--- Stop current speech
function TTSProvider:stop()
    -- Override in subclass
end

return TTSProvider
