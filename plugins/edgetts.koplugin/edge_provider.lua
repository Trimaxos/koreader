local TTSProvider = require("tts_provider")
local ltn12 = require("ltn12")
local logger = require("logger")

local EdgeProvider = TTSProvider:new{
    name = "edge",
    api_url = "https://tts.ngtri.io.vn/tts",
    voice = "vi-VN-HoaiMyNeural",
    rate = "+0%",
    pitch = "+0Hz",
    output_dir = nil,
}

function EdgeProvider:_buildRequest(text)
    local body = string.format(
        '{"text":"%s","voice":"%s","rate":"%s","pitch":"%s"}',
        text:gsub('"', '\\"'):gsub('\n', ' '):gsub('\r', ' '),
        self.voice,
        self.rate,
        self.pitch
    )
    return {
        url = self.api_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #body,
        },
        source = ltn12.source.string(body),
    }
end

function EdgeProvider:_getHttpModule()
    if self.api_url:match("^https://") then
        return require("ssl.https")
    end
    return require("socket.http")
end

function EdgeProvider:speak(text, on_complete, on_error)
    if not text or text == "" then
        if on_complete then on_complete() end
        return
    end

    if not self.output_dir then
        local DataStorage = require("datastorage")
        self.output_dir = DataStorage:getDataDir() .. "/edge_tts_cache/"
    end

    -- Ensure cache dir exists
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir(self.output_dir)

    local tmp_path = self.output_dir .. "edge_tts_" .. os.time() .. ".mp3"
    local tmp_file, err = io.open(tmp_path, "w+b")
    if not tmp_file then
        if on_error then on_error("Cannot write temp file: " .. tostring(err)) end
        return
    end

    local req = self:_buildRequest(text)
    req.sink = ltn12.sink.file(tmp_file)

    local http = self:_getHttpModule()
    local ok, status, headers, status_line = http.request(req)
    tmp_file:close()

    if ok and status == 200 then
        if self._android_play then
            local success = self._android_play(tmp_path)
            if success and on_complete then
                on_complete()
            elseif not success and on_error then
                on_error("Failed to play audio via Android MediaPlayer")
            end
        else
            if on_complete then on_complete() end
        end
    else
        if on_error then
            on_error(string.format("HTTP %d: %s", status or 0, tostring(ok or status_line)))
        end
        os.remove(tmp_path)
    end
end

function EdgeProvider:stop()
    if self._android_stop then
        self._android_stop()
    end
end

return EdgeProvider
