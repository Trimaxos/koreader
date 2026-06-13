--- Tests for TTS Controller
describe("TTS Controller", function()
    it("should load without errors", function()
        local TTSController = dofile("plugins/edgetts.koplugin/tts_controller.lua")
        check.not_nil(TTSController)
    end)

    it("should create instance with new()", function()
        local TTSController = dofile("plugins/edgetts.koplugin/tts_controller.lua")
        local ctrl = TTSController:new()
        check.not_nil(ctrl)
        check.not_nil(ctrl.start)
        check.not_nil(ctrl.stop)
        check.not_nil(ctrl.pause)
    end)

    it("should extract text from mock rolling document", function()
        local TTSController = dofile("plugins/edgetts.koplugin/tts_controller.lua")
        local ctrl = TTSController:new()
        local mock_ui = { rolling = true }
        ctrl:setUI(mock_ui)
        local mock_doc = {
            getTextFromPositions = function(_, p0, p1)
                return { text = "Hello, this is a test page content." }
            end
        }
        local text = ctrl:_getPageText(mock_doc)
        check.equal("Hello, this is a test page content.", text)
    end)

    it("should return empty string for nil document", function()
        local TTSController = dofile("plugins/edgetts.koplugin/tts_controller.lua")
        local ctrl = TTSController:new()
        local text = ctrl:_getPageText(nil)
        check.equal("", text)
    end)

    it("should handle paging mode documents", function()
        local TTSController = dofile("plugins/edgetts.koplugin/tts_controller.lua")
        local ctrl = TTSController:new()
        local mock_ui = { rolling = false, getCurrentPage = function() return 1 end }
        ctrl:setUI(mock_ui)
        local mock_doc = {
            getTextBoxes = function(_, page)
                return {
                    { { word = "Hello" }, { word = "world" } },
                    { { word = "This" }, { word = "is" }, { word = "a" }, { word = "test" } },
                }
            end
        }
        local text = ctrl:_getPageText(mock_doc)
        check.equal("Hello world This is a test", text)
    end)

    it("should start and stop cleanly", function()
        local TTSController = dofile("plugins/edgetts.koplugin/tts_controller.lua")
        local ctrl = TTSController:new()
        
        -- Use mock provider
        local mock_provider = {
            speak = function(self, text, on_complete, on_error)
                if on_complete then on_complete() end
            end,
            stop = function() end,
        }
        ctrl:setProvider(mock_provider)
        ctrl:setUI({ rolling = true, document = nil, handleEvent = function() end })
        
        -- Start should not crash
        ctrl:start()
        check.is_true(ctrl.is_reading)
        
        -- Stop should set state
        ctrl:stop()
        check.is_true(not ctrl.is_reading)
    end)

    it("should toggle pause/resume", function()
        local TTSController = dofile("plugins/edgetts.koplugin/tts_controller.lua")
        local ctrl = TTSController:new()
        local mock_provider = {
            speak = function(self, text, on_complete, on_error)
                if on_complete then on_complete() end
            end,
            stop = function() end,
        }
        ctrl:setProvider(mock_provider)
        ctrl:setUI({ rolling = true, document = nil, handleEvent = function() end })
        ctrl:start()
        
        ctrl:pause()
        check.is_true(ctrl.is_paused, "should be paused after pause()")
        
        ctrl:pause()
        check.is_true(not ctrl.is_paused, "should not be paused after resume")
    end)
end)
