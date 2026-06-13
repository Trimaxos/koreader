local TTSProvider = require("tts_provider")
local ltn12 = require("ltn12")
local logger = require("logger")

local EdgeProvider = TTSProvider:new{
    name = "edge",
    api_url = "https://tts.ngtri.io.vn/tts",
    api_key = "dCUHsBmDQJws88KGk_t1tl-fNGAORdOYdpkqPPNKGPI",
    voice = "vi-VN-HoaiMyNeural",
    rate = "+0%",
    pitch = "+0Hz",
    output_dir = nil,
    _media_player = nil,
}

function EdgeProvider:_buildRequest(text)
    -- Escape JSON special characters in text
    local escaped = text:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', ' '):gsub('\r', ' ')
    local body = string.format(
        '{"text":"%s","voice":"%s","rate":"%s","pitch":"%s"}',
        escaped,
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
            ["x-api-key"] = self.api_key or "",
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

--- Play audio via Android MediaPlayer using JNI.
--- Uses official KOReader's existing JNI bridge (no modded Android code needed).
function EdgeProvider:_playViaJNI(file_path, on_complete, on_error)
    local ok, android = pcall(require, "android")
    if not ok or not android or not android.app or not android.app.activity then
        if on_error then on_error("Android JNI bridge unavailable") end
        return
    end

    local ffi = require("ffi")

    android.jni:context(android.app.activity.vm, function(jni)
        local env = jni.env
        local mp_class = env[0].FindClass(env, "android/media/MediaPlayer")
        if mp_class == nil then
            if on_error then on_error("FindClass(MediaPlayer) failed") end
            return
        end

        -- Constructor: MediaPlayer()
        local ctor = env[0].GetMethodID(env, mp_class, "<init>", "()V")
        if ctor == nil then
            if on_error then on_error("GetMethodID(<init>)V) failed") end
            env[0].DeleteLocalRef(env, mp_class)
            return
        end

        local mp = env[0].NewObject(env, mp_class, ctor)
        if mp == nil then
            if on_error then on_error("NewObject(MediaPlayer) failed") end
            env[0].DeleteLocalRef(env, mp_class)
            return
        end

        -- Convert file path to Java String
        local path_str = env[0].NewStringUTF(env, file_path)
        if path_str == nil then
            env[0].DeleteLocalRef(env, mp)
            env[0].DeleteLocalRef(env, mp_class)
            if on_error then on_error("NewStringUTF failed") end
            return
        end

        -- setDataSource(String path)
        local set_ds = env[0].GetMethodID(env, mp_class, "setDataSource", "(Ljava/lang/String;)V")
        if set_ds == nil then
            env[0].DeleteLocalRef(env, path_str)
            env[0].DeleteLocalRef(env, mp)
            env[0].DeleteLocalRef(env, mp_class)
            if on_error then on_error("GetMethodID(setDataSource) failed") end
            return
        end
        env[0].CallVoidMethod(env, mp, set_ds, path_str)
        env[0].DeleteLocalRef(env, path_str)

        -- prepare()
        local prepare = env[0].GetMethodID(env, mp_class, "prepare", "()V")
        if prepare == nil then
            env[0].DeleteLocalRef(env, mp)
            env[0].DeleteLocalRef(env, mp_class)
            if on_error then on_error("GetMethodID(prepare) failed") end
            return
        end
        env[0].CallVoidMethod(env, mp, prepare)

        -- Create global ref so player survives JNI context
        local mp_global = env[0].NewGlobalRef(env, mp)
        self._media_player = mp_global

        -- Keep class ref for later method lookups
        local class_global = env[0].NewGlobalRef(env, mp_class)
        self._mp_class_global = class_global

        -- start()
        local start = env[0].GetMethodID(env, mp_class, "start", "()V")
        if start == nil then
            env[0].DeleteLocalRef(env, mp_global)
            env[0].DeleteLocalRef(env, class_global)
            self._media_player = nil
            self._mp_class_global = nil
            if on_error then on_error("GetMethodID(start) failed") end
            return
        end
        env[0].CallVoidMethod(env, mp, start)

        -- Delete local refs (global refs keep objects alive)
        env[0].DeleteLocalRef(env, mp)
        env[0].DeleteLocalRef(env, mp_class)
    end)

    -- Start polling for playback completion
    if self._media_player then
        self:_pollPlayback(on_complete, on_error)
    end
end

function EdgeProvider:_pollPlayback(on_complete, on_error)
    if not self._media_player then
        if on_complete then on_complete() end
        return
    end

    local ok, android = pcall(require, "android")
    if not ok then
        self:_releaseMediaPlayer()
        if on_complete then on_complete() end
        return
    end

    local ffi = require("ffi")
    local is_playing = false

    android.jni:context(android.app.activity.vm, function(jni)
        local env = jni.env
        local is_playing_mid = env[0].GetMethodID(env, self._mp_class_global, "isPlaying", "()Z")
        if is_playing_mid then
            is_playing = env[0].CallBooleanMethod(env, self._media_player, is_playing_mid) ~= 0
        end
    end)

    if is_playing then
        -- Still playing, poll again in 500ms
        local UIManager = require("ui/uimanager")
        UIManager:scheduleIn(0.5, function()
            self:_pollPlayback(on_complete, on_error)
        end)
    else
        -- Done, cleanup and callback
        self:_releaseMediaPlayer()
        if on_complete then on_complete() end
    end
end

function EdgeProvider:_releaseMediaPlayer()
    if not self._media_player then return end

    local ok, android = pcall(require, "android")
    if not ok then
        self._media_player = nil
        self._mp_class_global = nil
        return
    end

    local ffi = require("ffi")

    android.jni:context(android.app.activity.vm, function(jni)
        local env = jni.env
        local mp = self._media_player
        local cls = self._mp_class_global

        -- stop()
        local stop_mid = env[0].GetMethodID(env, cls, "stop", "()V")
        if stop_mid then
            env[0].CallVoidMethod(env, mp, stop_mid)
        end

        -- release()
        local release_mid = env[0].GetMethodID(env, cls, "release", "()V")
        if release_mid then
            env[0].CallVoidMethod(env, mp, release_mid)
        end

        -- Delete global refs
        env[0].DeleteGlobalRef(env, mp)
        env[0].DeleteGlobalRef(env, cls)
    end)

    self._media_player = nil
    self._mp_class_global = nil
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
        -- Play via JNI directly (no Kotlin dependency)
        self:_playViaJNI(tmp_path, on_complete, on_error)
    else
        if on_error then
            on_error(string.format("HTTP %d: %s", status or 0, tostring(ok or status_line)))
        end
        os.remove(tmp_path)
    end
end

function EdgeProvider:stop()
    self:_releaseMediaPlayer()
end

return EdgeProvider
