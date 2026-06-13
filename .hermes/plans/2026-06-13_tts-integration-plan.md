# Edge TTS Integration into KOReader — Implementation Plan

> **For Hermes:** Use test-driven development throughout. Each task = 2-5 min.

**Goal:** Add TTS reading to KOReader with two providers: Edge TTS (HTTP API) and Android System TTS (TextToSpeech), enabling continuous reading with auto-page-turn.

**Architecture:**
```
Plugin (Lua) ──HTTP──► Edge TTS Server (Boss's API)
      │
      ├──► Android JNI Bridge ──► MediaPlayer (Edge TTS audio files)
      └──► Android JNI Bridge ──► TextToSpeech (System TTS)
```

**Tech Stack:**
- Lua (KOReader plugin), busted (tests)
- Kotlin (Android JNI bridge)
- LuaSocket (`socket.http` / `ssl.https`)
- Android MediaPlayer + TextToSpeech

**Prerequisites check before starting:**
- Android SDK at `~/tools/android-sdk`
- JDK 17 at `~/tools/jdk-17.0.13+11`
- Gradle wrapper in `platform/android/luajit-launcher/`

---

## Phase 0: Verify Environment & Test Setup

### Task 0.1: Verify Android build env runs

**Objective:** Confirm `./gradlew assembleDebug` compiles without our changes yet

**Files:**
- Modify: none yet (read-only check)
- Test: `platform/android/luajit-launcher/`

**Step 1: Check build prerequisites**

Run:
```bash
cd ~/projects/koreader
ls platform/android/luajit-launcher/gradlew
echo "---"
ls ~/tools/android-sdk/
echo "---"
ls ~/tools/jdk-17.0.13+11/bin/java
```

Expected: All paths exist

**Step 2: Dry-run gradle check (noop assemble)**

Run:
```bash
cd platform/android/luajit-launcher
export JAVA_HOME=~/tools/jdk-17.0.13+11
export ANDROID_HOME=~/tools/android-sdk
./gradlew tasks --group="build" 2>&1 | head -20
```

Expected: Shows build tasks including `assembleDebug`

**Step 3: Verify busted test runner**

KOReader tests use busted. Check if busted is available:
```bash
cd ~/projects/koreader
which busted 2>/dev/null || find . -name "busted" -type f 2>/dev/null | head -3
```

If not installed, install:
```bash
luarocks install busted
```

**Step 4: Run an existing test to verify test infra**

Run:
```bash
cd ~/projects/koreader
./kodev test --busted -- --filter="hello" spec/unit/ 2>&1 | tail -20
```

(Or a simpler test that doesn't need full build)
```bash
cd ~/projects/koreader && ls spec/unit/*.lua | head -5
busted spec/unit/some_simple_spec.lua 2>&1 | head -20
```

---

### Task 0.2: Write a mock plugin test spec

**Objective:** Verify we can test a KOReader plugin under busted

**Files:**
- Create: `spec/unit/edgetts_spec.lua`

**Step 1: Create test file**

```lua
local commonrequire = require("commonrequire")

describe("EdgeTTS plugin", function()
    it("should load plugin without errors", function()
        local ok, err = pcall(function()
            require("plugins/edgetts.koplugin/main")
        end)
        assert.is_true(ok, err or "plugin failed to load")
    end)
end)
```

**Step 2: Run test to verify failure**

Run:
```bash
busted spec/unit/edgetts_spec.lua 2>&1
```

Expected: FAIL — "module 'plugins/edgetts.koplugin/main' not found"

**Step 3: Commit**

```bash
cd ~/projects/koreader
git add spec/unit/edgetts_spec.lua
git commit -m "test: add placeholder spec for EdgeTTS plugin"
```

---

## Phase 1: Android JNI Bridge — Audio Playback

### Task 1.1: Add `playAudio` and `stopAudio` to `LuaInterface.kt`

**Objective:** Declare methods that Lua can call via JNI for audio playback

**Files:**
- Modify: `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/LuaInterface.kt`

**Step 1: Write the test (in mind — Kotlin JNI tests need device, so it's compile-time verified)**

**Step 2: Add method declarations**

Add after `showToast` (line 83):
```kotlin
fun playAudio(path: String): Int
fun stopAudio()
```

The full interface now has 2 new methods.

**Step 3: Verify compilation**

```bash
cd platform/android/luajit-launcher
export JAVA_HOME=~/tools/jdk-17.0.13+11
export ANDROID_HOME=~/tools/android-sdk
./gradlew compileDebugKotlin 2>&1 | tail -20
```

Expected: BUILD SUCCESSFUL

**Step 4: Commit**

```bash
git add platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/LuaInterface.kt
git commit -m "feat(android): add playAudio/stopAudio to Lua JNI interface"
```

---

### Task 1.2: Implement `playAudio` / `stopAudio` in `MainActivity.kt`

**Objective:** Implement the audio playback using Android MediaPlayer

**Files:**
- Modify: `platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/MainActivity.kt`

**Step 1: Implement the methods**

Add to MainActivity.kt (at the end of the `override fun` section, before line 380 or so):

```kotlin
private var mediaPlayer: MediaPlayer? = null

override fun playAudio(path: String): Int {
    return try {
        stopAudio() // Stop any existing playback
        mediaPlayer = MediaPlayer().apply {
            setDataSource(path)
            setOnCompletionListener {
                Log.i(tag, "Audio playback completed: $path")
            }
            setOnErrorListener { _, what, extra ->
                Log.e(tag, "MediaPlayer error: what=$what extra=$extra")
                true
            }
            prepare()
            start()
        }
        Log.i(tag, "Playing audio: $path")
        0 // success
    } catch (e: Exception) {
        Log.e(tag, "Failed to play audio: ${e.message}")
        -1 // error
    }
}

override fun stopAudio() {
    mediaPlayer?.apply {
        if (isPlaying) {
            stop()
        }
        release()
    }
    mediaPlayer = null
}
```

Add import:
```kotlin
import android.media.MediaPlayer
```

**Step 2: Verify compilation**

```bash
cd platform/android/luajit-launcher
export JAVA_HOME=~/tools/jdk-17.0.13+11
export ANDROID_HOME=~/tools/android-sdk
./gradlew compileDebugKotlin 2>&1 | tail -20
```

Expected: BUILD SUCCESSFUL

**Step 3: Commit**

```bash
git add platform/android/luajit-launcher/app/src/main/java/org/koreader/launcher/MainActivity.kt
git commit -m "feat(android): implement playAudio/stopAudio with MediaPlayer"
```

---

### Task 1.3: Expose `playAudio` / `stopAudio` via `assets/android.lua`

**Objective:** Add Lua-side FFI bindings so the plugin can call `android.playAudio(path)` and `android.stopAudio()`

**Files:**
- Modify: `platform/android/luajit-launcher/assets/android.lua`

**Step 1: Add function wrappers**

After the `android.importFile` function (around line 1688):

```lua
android.playAudio = function(path)
    return JNI:context(android.app.activity.vm, function(jni)
        local jni_path = jni.env[0].NewStringUTF(jni.env, path)
        local result = jni:callIntMethod(
            android.app.activity.clazz,
            "playAudio",
            "(Ljava/lang/String;)I",
            jni_path
        )
        jni.env[0].DeleteLocalRef(jni.env, jni_path)
        return result == 0
    end)
end

android.stopAudio = function()
    return JNI:context(android.app.activity.vm, function(jni)
        jni:callVoidMethod(
            android.app.activity.clazz,
            "stopAudio",
            "()V"
        )
    end)
end
```

**Step 2: Verify with a dry-run Lua syntax check**

```bash
luacheck platform/android/luajit-launcher/assets/android.lua 2>&1 | tail -5
```

(If luacheck not available: `luajit -bl platform/android/luajit-launcher/assets/android.lua /dev/null 2>&1`)

Expected: No errors

**Step 3: Commit**

```bash
git add platform/android/luajit-launcher/assets/android.lua
git commit -m "feat(android): expose playAudio/stopAudio to Lua via JNI"
```

---

### Task 1.4: Add `ttsSpeak` / `ttsStop` to `LuaInterface.kt` and `MainActivity.kt`

**Objective:** Add System TTS (Android TextToSpeech) as the second provider

**Files:**
- Modify: `LuaInterface.kt`, `MainActivity.kt`

**Step 1: Add to LuaInterface.kt**

```kotlin
fun ttsSpeak(text: String): Int
fun ttsStop()
```

**Step 2: Implement in MainActivity.kt**

```kotlin
private var textToSpeech: TextToSpeech? = null
private var ttsReady = false

override fun ttsSpeak(text: String): Int {
    return try {
        if (textToSpeech == null) {
            textToSpeech = TextToSpeech(this) { status ->
                ttsReady = (status == TextToSpeech.SUCCESS)
                if (ttsReady) {
                    // Set Vietnamese language
                    val result = textToSpeech?.setLanguage(Locale.forLanguageTag("vi-VN"))
                    Log.i(tag, "TTS initialized, lang result: $result")
                }
            }
        }
        if (ttsReady) {
            textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "tts_utterance")
            0 // success
        } else {
            Log.w(tag, "TTS not ready yet")
            -2 // not ready
        }
    } catch (e: Exception) {
        Log.e(tag, "TTS speak failed: ${e.message}")
        -1 // error
    }
}

override fun ttsStop() {
    textToSpeech?.stop()
}
```

Add imports:
```kotlin
import android.speech.tts.TextToSpeech
import java.util.Locale
```

Add cleanup in `onDestroy()`:
```kotlin
override fun onDestroy() {
    textToSpeech?.shutdown()
    textToSpeech = null
    stopAudio() // also stop media player
    super.onDestroy()
}
```

**Step 3: Verify compilation**

```bash
cd platform/android/luajit-launcher
export JAVA_HOME=~/tools/jdk-17.0.13+11
export ANDROID_HOME=~/tools/android-sdk
./gradlew compileDebugKotlin 2>&1 | tail -20
```

Expected: BUILD SUCCESSFUL

**Step 4: Expose in assets/android.lua**

```lua
android.ttsSpeak = function(text)
    return JNI:context(android.app.activity.vm, function(jni)
        local jni_text = jni.env[0].NewStringUTF(jni.env, text)
        local result = jni:callIntMethod(
            android.app.activity.clazz,
            "ttsSpeak",
            "(Ljava/lang/String;)I",
            jni_text
        )
        jni.env[0].DeleteLocalRef(jni.env, jni_text)
        return result == 0 or result == -2  -- -2 = not ready, retry later
    end)
end

android.ttsStop = function()
    return JNI:context(android.app.activity.vm, function(jni)
        jni:callVoidMethod(
            android.app.activity.clazz,
            "ttsStop",
            "()V"
        )
    end)
end
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(android): add System TTS (TextToSpeech) JNI bridge"
```

---

## Phase 2: Edge TTS Plugin — Core Engine

### Task 2.1: Create plugin skeleton with _meta.lua and main.lua

**Objective:** Create the bare plugin structure that registers in KOReader's menu

**Files:**
- Create: `plugins/edgetts.koplugin/_meta.lua`
- Create: `plugins/edgetts.koplugin/main.lua`
- Test: `spec/unit/edgetts_spec.lua` (update)

**Step 1: Write failing test**

Update `spec/unit/edgetts_spec.lua`:

```lua
describe("EdgeTTS plugin", function()
    it("should load plugin without errors", function()
        local ok, err = pcall(function()
            require("plugins/edgetts.koplugin/main")
        end)
        assert.is_true(ok, err or "plugin failed to load")
    end)

    it("should have _meta with title and version", function()
        local meta = require("plugins/edgetts.koplugin/_meta")
        assert.is_not_nil(meta.title)
        assert.is_not_nil(meta.version)
    end)

    it("should register to main menu", function()
        local plugin = require("plugins/edgetts.koplugin/main")
        local menu_items = {}
        plugin:addToMainMenu(menu_items)
        assert.is_not_nil(menu_items.edgetts)
        assert.are_equal("Edge TTS", menu_items.edgetts.text)
    end)
end)
```

Run test — expected: FAIL (files don't exist yet)

**Step 2: Create _meta.lua**

```lua
--[[--
Edge TTS — Text-to-Speech reading with Edge TTS and Android System TTS.

@module koplugin.EdgeTTS
--]]--

return {
    title = "Edge TTS",
    description = "Text-to-Speech reading with Edge TTS and Android System TTS",
    version = 1,
    priority = 10,
}
```

**Step 3: Create main.lua** (minimal skeleton)

```lua
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local EdgeTTS = WidgetContainer:extend{
    name = "edgetts",
    is_doc_only = false,
}

function EdgeTTS:init()
    self.ui.menu:registerToMainMenu(self)
end

function EdgeTTS:addToMainMenu(menu_items)
    menu_items.edgetts = {
        text = _("Edge TTS"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Play"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("Edge TTS will start reading..."),
                    })
                end,
            },
            {
                text = _("Stop"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("Edge TTS stopped"),
                    })
                end,
            },
            {
                text = _("Settings"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("TTS Settings"),
                    })
                end,
            },
        },
    }
end

return EdgeTTS
```

**Step 4: Run tests**

```bash
busted spec/unit/edgetts_spec.lua 2>&1
```

Expected: All 3 tests PASS (or at least the load + meta tests)

**Step 5: Commit**

```bash
git add plugins/edgetts.koplugin/ spec/unit/edgetts_spec.lua
git commit -m "feat(edgetts): create plugin skeleton with menu registration"
```

---

### Task 2.2: Implement `TTSProvider` interface + `EdgeProvider`

**Objective:** Create the TTS provider abstraction and Edge TTS HTTP client

**Files:**
- Create: `plugins/edgetts.koplugin/tts_provider.lua`
- Create: `plugins/edgetts.koplugin/edge_provider.lua`
- Modify: `plugins/edgetts.koplugin/main.lua`
- Create: `spec/unit/edge_provider_spec.lua`

**Step 1: Write test for TTSProvider interface**

`spec/unit/edge_provider_spec.lua`:
```lua
describe("Edge TTS Provider", function()
    it("should require without errors", function()
        local ok, err = pcall(require, "plugins/edgetts.koplugin/edge_provider")
        assert.is_true(ok, err)
    end)

    it("should have speak and stop methods", function()
        local EdgeProvider = require("plugins/edgetts.koplugin/edge_provider")
        assert.is_not_nil(EdgeProvider.speak)
        assert.is_not_nil(EdgeProvider.stop)
    end)

    it("should build correct HTTP request", function()
        local EdgeProvider = require("plugins/edgetts.koplugin/edge_provider")
        local request = EdgeProvider:_buildRequest("Xin chào", {})
        assert.is_not_nil(request)
        assert.are_equal("POST", request.method)
        assert.are_equal("https://tts.ngtri.io.vn/tts", request.url)
        assert.is_not_nil(request.body)
    end)
end)
```

Run: expected FAIL

**Step 2: Create `tts_provider.lua`**

```lua
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
    -- Override in subclass
    error("TTSProvider:speak() must be implemented")
end

--- Stop current speech
function TTSProvider:stop()
    -- Override in subclass
end

return TTSProvider
```

**Step 3: Create `edge_provider.lua`**

```lua
local TTSProvider = require("plugins/edgetts.koplugin/tts_provider")
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local logger = require("logger")

local EdgeProvider = TTSProvider:new{
    name = "edge",
    api_url = "https://tts.ngtri.io.vn/tts",
    voice = "vi-VN-HoaiMyNeural",
    rate = "+0%",
    pitch = "+0Hz",
    output_dir = nil,  -- set at runtime
}

function EdgeProvider:_buildRequest(text, text_lang)
    local body = string.format(
        '{"text":"%s","voice":"%s","rate":"%s","pitch":"%s"}',
        text:gsub('"', '\\"'):gsub('\n', ' '),
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
        sink = ltn12.sink.null(), -- will be replaced in speak()
    }
end

function EdgeProvider:speak(text, on_complete, on_error)
    if not text or text == "" then
        if on_complete then on_complete() end
        return
    end
    
    -- Build temp file path
    local tmp_path = self.output_dir .. "/edge_tts_" .. os.time() .. ".mp3"
    local tmp_file, err = io.open(tmp_path, "w+b")
    if not tmp_file then
        if on_error then on_error("Cannot write temp file: " .. tostring(err)) end
        return
    end
    
    -- Build request with file sink
    local req = self:_buildRequest(text)
    req.sink = ltn12.sink.file(tmp_file)
    
    -- Make HTTP request
    local ok, status, headers, status_line
    if self.api_url:match("^https://") then
        ok, status, headers, status_line = https.request(req)
    else
        ok, status, headers, status_line = http.request(req)
    end
    
    tmp_file:close()
    
    if ok and status == 200 then
        -- Play via Android MediaPlayer
        if self._android_play then
            local success = self._android_play(tmp_path)
            if success and on_complete then
                -- Note: for sync playback, call on_complete immediately
                -- For async, we need a callback mechanism
                on_complete()
            elseif not success and on_error then
                on_error("Failed to play audio")
            end
        else
            -- Playing not set up yet, but file was saved
            if on_complete then on_complete() end
        end
    else
        if on_error then
            on_error(string.format("HTTP %d: %s", status or 0, tostring(ok or status_line)))
        end
        -- Clean up failed download
        os.remove(tmp_path)
    end
end

function EdgeProvider:stop()
    if self._android_stop then
        self._android_stop()
    end
end

return EdgeProvider
```

**Step 4: Run tests**

```bash
busted spec/unit/edge_provider_spec.lua 2>&1
```

Expected: Tests PASS (the _buildRequest test verifies structure, no actual HTTP calls in unit tests)

**Step 5: Commit**

```bash
git add plugins/edgetts.koplugin/tts_provider.lua plugins/edgetts.koplugin/edge_provider.lua spec/unit/edge_provider_spec.lua
git commit -m "feat(edgetts): add TTSProvider interface and EdgeProvider implementation"
```

---

### Task 2.3: Create `SystemProvider` for Android TTS

**Objective:** Implement the system TTS provider using Android's TextToSpeech

**Files:**
- Create: `plugins/edgetts.koplugin/system_provider.lua`
- Create: `spec/unit/system_provider_spec.lua`

**Step 1: Write failing test**

```lua
describe("System TTS Provider", function()
    it("should require without errors", function()
        local ok, err = pcall(require, "plugins/edgetts.koplugin/system_provider")
        assert.is_true(ok, err)
    end)

    it("should have speak and stop methods", function()
        local SystemProvider = require("plugins/edgetts.koplugin/system_provider")
        assert.is_not_nil(SystemProvider.speak)
        assert.is_not_nil(SystemProvider.stop)
    end)
end)
```

**Step 2: Create system_provider.lua**

```lua
local TTSProvider = require("plugins/edgetts.koplugin/tts_provider")
local logger = require("logger")

local SystemProvider = TTSProvider:new{
    name = "system",
}

-- Check if running on Android with JNI available
local has_android = false
local android_available = pcall(function()
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
            local err_msg = (result == false and "Android TextToSpeech not initialized") or "TTS failed"
            on_error(err_msg)
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
```

**Step 3: Run tests**

```bash
busted spec/unit/system_provider_spec.lua 2>&1
```

Expected: PASS

**Step 4: Commit**

```bash
git add plugins/edgetts.koplugin/system_provider.lua spec/unit/system_provider_spec.lua
git commit -m "feat(edgetts): add System TTS provider using Android TextToSpeech"
```

---

### Task 2.4: Create `TTSController` — Orchestrator

**Objective:** Main controller that manages TTS state, text extraction, page turning, and continuous reading loop

**Files:**
- Create: `plugins/edgetts.koplugin/tts_controller.lua`
- Create: `spec/unit/tts_controller_spec.lua`

**Step 1: Write failing test**

```lua
describe("TTS Controller", function()
    it("should require without errors", function()
        local ok, err = pcall(require, "plugins/edgetts.koplugin/tts_controller")
        assert.is_true(ok, err)
    end)

    it("should have start, stop, pause methods", function()
        local TTSController = require("plugins/edgetts.koplugin/tts_controller")
        assert.is_not_nil(TTSController.start)
        assert.is_not_nil(TTSController.stop)
        assert.is_not_nil(TTSController.pause)
    end)

    it("should extract text from current page", function()
        local TTSController = require("plugins/edgetts.koplugin/tts_controller")
        -- Mock document with getTextFromPositions
        local mock_doc = {
            getTextFromPositions = function(_, p0, p1)
                return { text = "Hello, this is a test page." }
            end
        }
        local text = TTSController:_getPageText(mock_doc)
        assert.are_equal("Hello, this is a test page.", text)
    end)
end)
```

**Step 2: Create `tts_controller.lua`**

```lua
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

--- Extract text from the current visible page
-- For rolling mode (EPUB): getTextFromPositions((0,0) to (scr_w, scr_h))
-- For paging mode (PDF): getTextBoxes(page)
function TTSController:_getPageText(document)
    if not document then return "" end
    
    if self.ui and self.ui.rolling then
        local res = document:getTextFromPositions(
            {x = 0, y = 0},
            {x = Screen:getWidth(), y = Screen:getHeight()},
            true -- do not draw selection
        )
        if res and res.text then
            return res.text
        end
    else
        -- Paging mode (PDF)
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

--- Start reading from current page
function TTSController:start()
    if not self.provider or not self.ui then return end
    self.is_reading = true
    self.is_paused = false
    self:_readCurrentPage()
end

--- Read the current page content
function TTSController:_readCurrentPage()
    if not self.is_reading or self.is_paused then return end
    
    local text = self:_getPageText(self.ui.document)
    self.current_text = text
    
    if not text or text == "" then
        -- Empty page, try next page
        self:_nextPage()
        return
    end
    
    -- Trim whitespace
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        self:_nextPage()
        return
    end
    
    -- Speak via provider
    self.provider:speak(text, 
        function() -- on_complete
            logger.dbg("TTS: Page finished, advancing to next page")
            self:_nextPage()
        end,
        function(err) -- on_error
            logger.warn("TTS Error: " .. tostring(err))
            self:stop()
        end
    )
end

--- Advance to the next page and continue reading
function TTSController:_nextPage()
    if not self.is_reading or self.is_paused then return end
    
    -- Send event to turn page
    if self.ui then
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
        -- Wait briefly for page to render, then read
        -- In KOReader, we schedule the next read after render
        local UIManager = require("ui/uimanager")
        UIManager:scheduleIn(0.3, function()
            self:_readCurrentPage()
        end)
    end
end

--- Pause/resume reading
function TTSController:pause()
    if self.is_reading then
        if self.is_paused then
            -- Resume
            self.is_paused = false
            self:_readCurrentPage()
        else
            -- Pause
            self.is_paused = true
            if self.provider then
                self.provider:stop()
            end
        end
    end
end

--- Stop reading entirely
function TTSController:stop()
    self.is_reading = false
    self.is_paused = false
    if self.provider then
        self.provider:stop()
    end
end

return TTSController
```

**Step 3: Run tests**

```bash
busted spec/unit/tts_controller_spec.lua 2>&1
```

Expected: All 3 tests PASS

**Step 4: Commit**

```bash
git add plugins/edgetts.koplugin/tts_controller.lua spec/unit/tts_controller_spec.lua
git commit -m "feat(edgetts): add TTSController with page text extraction and auto-next-page"
```

---

### Task 2.5: Wire everything together in `main.lua`

**Objective:** Connect controller + providers + UI in the plugin's main module

**Files:**
- Modify: `plugins/edgetts.koplugin/main.lua`

**Step 1: Write failing test**

Update `spec/unit/edgetts_spec.lua`:
```lua
describe("EdgeTTS plugin", function()
    it("should load plugin without errors", function()
        local ok, err = pcall(require, "plugins/edgetts.koplugin/main")
        assert.is_true(ok, err)
    end)

    it("should expose init method", function()
        local plugin = require("plugins/edgetts.koplugin/main")
        assert.is_not_nil(plugin.init)
    end)

    it("should have provider switching", function()
        local plugin = require("plugins/edgetts.koplugin/main")
        local providers = plugin._getProviders()
        assert.is_not_nil(providers)
        assert.is_not_nil(providers.edge)
        assert.is_not_nil(providers.system)
    end)
end)
```

**Step 2: Rewrite main.lua**

```lua
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")
local logger = require("logger")
local _ = require("gettext")
local TTSController = require("plugins/edgetts.koplugin/tts_controller")
local EdgeProvider = require("plugins/edgetts.koplugin/edge_provider")
local SystemProvider = require("plugins/edgetts.koplugin/system_provider")
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
    -- Check if Android with JNI
    local android_ok, _ = pcall(require, "android")
    
    -- Initialize providers
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
    
    -- Create controller
    self.controller = TTSController:new()
    self.controller:setUI(self.ui)
    self.controller:setProvider(self.providers[self.current_provider] or edge)
    
    -- Register menu
    self.ui.menu:registerToMainMenu(self)
    
    -- Register for reader events
    self.ui:registerPostInitCallback(function()
        self.ui.menu:registerToMainMenu(self)
    end)
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
                    if not self.controller then return end
                    self.controller:stop() -- Stop if reading
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
    if self.providers.edge then
        table.insert(options, "Edge TTS")
    end
    if self.providers.system then
        table.insert(options, "System TTS")
    end
    
    if #options == 0 then
        UIManager:show(InfoMessage:new{ text = _("No TTS providers available") })
        return
    end
    
    -- Toggle between available providers
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
    -- Build settings submenu
    -- TODO: expand into full settings widget
    local settings_items = {
        {
            text = _("Voice: ") .. self.settings.voice,
            callback = function()
                -- Simple voice toggle
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
        {
            text = _("Edge TTS URL: ") .. self.settings.api_url,
            callback = function()
                -- In future: text input widget
                UIManager:show(InfoMessage:new{
                    text = _("URL can be changed in settings code"),
                })
            end,
        },
    }
    
    -- Show as touch menu
    local TouchMenu = require("ui/widget/touchmenu")
    UIManager:show(TouchMenu:new{
        title = _("TTS Settings"),
        item_table = settings_items,
    })
end

return EdgeTTS
```

**Step 3: Run tests**

```bash
busted spec/unit/edgetts_spec.lua 2>&1
```

Expected: All 3 tests PASS

**Step 4: Commit**

```bash
git add plugins/edgetts.koplugin/main.lua spec/unit/edgetts_spec.lua
git commit -m "feat(edgetts): wire controller+providers+menu in main plugin"
```

---

## Phase 3: Build & Integration Test

### Task 3.1: Build APK for Android

**Objective:** Compile the full KOReader Android APK with our changes

**Files:**
- Modify: none (build only)

**Step 1: Setup env**

```bash
cd ~/projects/koreader
export JAVA_HOME=~/tools/jdk-17.0.13+11
export ANDROID_HOME=~/tools/android-sdk
export ANDROID_NDK_HOME=~/tools/android-sdk/ndk/...  # find the right ndk
```

**Step 2: Check NDK availability**

```bash
ls ~/tools/android-sdk/ndk/
```

**Step 3: Build**

```bash
cd platform/android/luajit-launcher
./gradlew assembleDebug 2>&1 | tail -50
```

Expected: BUILD SUCCESSFUL → APK at `app/build/outputs/apk/debug/`

**Step 4: If build fails**, troubleshoot:
- Missing NDK → `sdkmanager "ndk;25.2.9519653"`
- Missing dependencies → check `build.gradle`

**Step 5: Commit build scripts if any setup needed**

```bash
git add platform/android/luajit-launcher/gradle.properties
git commit -m "chore: android build configuration"
```

---

### Task 3.2: Install APK and Test on Device

**Objective:** Test TTS works on actual Android device

**Step 1: Install APK**

```bash
adb install -r platform/android/luajit-launcher/app/build/outputs/apk/debug/app-debug.apk
```

**Step 2: Manual test checklist**

| Test Case | Expected |
|---|---|
| Open EPUB book | KOReader loads book |
| Menu → More Tools → Edge TTS → Start Reading | TTS starts speaking page content |
| Text is spoken in Vietnamese | Edge TTS returns correct audio |
| Audio plays through speaker | MediaPlayer works |
| Page auto-turns after speech | Next page content loads |
| Pause / Resume | TTS pauses, resumes from next page |
| Stop | TTS stops, no background playback |
| Switch to System TTS | Android TextToSpeech reads aloud |
| Close book while TTS playing | TTS stops, no errors |
| Continuous reading | Reads chapter to end, doesn't stop |

**Step 3: Log any failures**

```bash
adb logcat | grep -E "EdgeTTS|MediaPlayer|TextToSpeech|NativeThread" 2>&1
```

---

## Risks & Open Questions

| Risk | Mitigation |
|---|---|
| **Async audio completion callback** — MediaPlayer `setOnCompletionListener` is async but our Lua call pattern is sync | Use `UIManager:scheduleIn()` with estimated duration, or add a JNI callback mechanism |
| **Text too long** — Edge TTS API may reject long text | Chunk text by sentences before sending |
| **Chinese/Vietnamese characters in HTTP JSON** — encoding issues | Ensure UTF-8 encoding in HTTP headers |
| **File cleanup** — temp MP3 files accumulate | Clean up cache dir on start |
| **TTS not ready (System)** — Android TTS init is async | Retry after 500ms if status = -2 |
| **No internet (Edge TTS)** | Fall back gracefully with error message |
| **Screen size dependency** — `getTextFromPositions` depends on screen dimensions | Already using `Screen:getWidth()/getHeight()` |
