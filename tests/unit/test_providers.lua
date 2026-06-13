--- Tests for TTS Provider classes

describe("TTS Providers", function()
    it("should load TTSProvider interface", function()
        local TTSProvider = dofile("plugins/edgetts.koplugin/tts_provider.lua")
        check.not_nil(TTSProvider)
        local instance = TTSProvider:new({ name = "test" })
        check.not_nil(instance)
        check.equal("test", instance.name)
    end)

    it("should throw error when calling abstract speak()", function()
        local TTSProvider = dofile("plugins/edgetts.koplugin/tts_provider.lua")
        local instance = TTSProvider:new({})
        local ok, err = pcall(instance.speak, instance, "text", nil, nil)
        check.ok(not ok, "speak should throw on abstract")
    end)

    it("should load edge_provider", function()
        local EdgeProvider = dofile("plugins/edgetts.koplugin/edge_provider.lua")
        check.not_nil(EdgeProvider)
        check.not_nil(EdgeProvider.speak)
        check.not_nil(EdgeProvider.stop)
    end)

    it("should build correct HTTP request body", function()
        local EdgeProvider = dofile("plugins/edgetts.koplugin/edge_provider.lua")
        local provider = EdgeProvider:new{
            api_url = "https://tts.ngtri.io.vn/tts",
            api_key = "test-key-123",
            voice = "vi-VN-HoaiMyNeural",
            rate = "+0%",
        }
        local req = provider:_buildRequest("Xin chào thế giới", {})
        check.not_nil(req)
        check.equal("POST", req.method)
        check.not_nil(req.source, "request should have ltn12 source")
        check.not_nil(req.headers["x-api-key"], "request should have api key header")
        check.equal("test-key-123", req.headers["x-api-key"])
        -- Test that source produces correct data
        local src_fn = req.source
        local chunk = src_fn()
        check.not_nil(chunk, "source should produce data")
        check.ok(chunk:match('"Xin chào'), "source should contain the input text")
        check.ok(chunk:match("vi%-VN%-HoaiMyNeural"), "source should contain the voice")
    end)

    it("should handle empty text gracefully", function()
        local EdgeProvider = dofile("plugins/edgetts.koplugin/edge_provider.lua")
        local provider = EdgeProvider:new{ api_url = "https://test.tts/" }
        local completed = false
        provider:speak("", function() completed = true end)
        check.is_true(completed, "should call on_complete for empty text")
    end)

    it("should load system_provider", function()
        local SystemProvider = dofile("plugins/edgetts.koplugin/system_provider.lua")
        check.not_nil(SystemProvider)
        check.not_nil(SystemProvider.speak)
        check.not_nil(SystemProvider.stop)
    end)
end)
