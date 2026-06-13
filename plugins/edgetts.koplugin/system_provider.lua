local TTSProvider = require("tts_provider")
local logger = require("logger")

local SystemProvider = TTSProvider:new{
    name = "system",
}

local has_android = false
pcall(function()
    local android = require("android")
    has_android = (android ~= nil)
end)

function SystemProvider:speak(text, on_complete, on_error)
    if not has_android then
        if on_error then on_error("Android TTS not available on this platform") end
        return
    end

    local android = require("android")
    local result = android.ttsSpeak(text)

    if result then
        if on_complete then on_complete() end
    else
        if on_error then
            on_error("Android TextToSpeech failed or not initialized")
        end
    end
end

function SystemProvider:stop()
    if has_android then
        local android = require("android")
        android.ttsStop()
    end
end

return SystemProvider
