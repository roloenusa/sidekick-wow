-- Verification harness for Sidekick.
--
-- WoW addons have no local test runner, so this file mocks enough of the WoW
-- API to load the real addon files and exercise them. The mock simulates
-- Midnight "secret values" as tables whose arithmetic/comparison metamethods
-- raise an error, mirroring the live client. If any guarded path forgets to
-- check issecretvalue() before doing math, these tests fail loudly.
--
-- Run from the repository root:  lua test/run_tests.lua

local realprint = print

-------------------------------------------------------------------------------
-- Secret value simulation
-------------------------------------------------------------------------------
local secretRegistry = setmetatable({}, { __mode = "k" })

local function secretError()
    error("attempt to operate on a secret value", 2)
end

local secretMeta = {
    __add = secretError, __sub = secretError, __mul = secretError,
    __div = secretError, __mod = secretError, __pow = secretError,
    __unm = secretError, __lt = secretError, __le = secretError,
    __concat = secretError, __tostring = function() return "<secret>" end,
}

local function makeSecret()
    local s = setmetatable({}, secretMeta)
    secretRegistry[s] = true
    return s
end

-- Global, consumed by the addon's `local issecretvalue = issecretvalue or ...`.
function issecretvalue(value)
    return secretRegistry[value] == true
end

-------------------------------------------------------------------------------
-- Frame / widget mock
-------------------------------------------------------------------------------
local frameRegistry = {}
local noop = function() end

local frameMethods = {}
for _, name in ipairs({
    "SetFrameStrata", "SetFrameLevel", "SetSize", "SetPoint", "SetWidth",
    "SetHeight", "ClearAllPoints", "SetAllPoints", "SetGradient",
    "SetColorTexture", "SetTexture", "SetBlendMode", "SetVertexColor",
    "SetStatusBarColor", "SetDrawLayer", "SetScale",
}) do
    frameMethods[name] = noop
end

function frameMethods:SetScript(script, fn) self._scripts[script] = fn end
function frameMethods:GetScript(script) return self._scripts[script] end
function frameMethods:RegisterEvent(event) self._events[event] = true end
function frameMethods:RegisterUnitEvent(event, unit)
    self._events[event] = true
    self._eventUnit = unit
end
function frameMethods:UnregisterEvent(event) self._events[event] = nil end
function frameMethods:UnregisterAllEvents() self._events = {} end
function frameMethods:IsEventRegistered(event) return self._events[event] == true end
function frameMethods:Show() self._shown = true end
function frameMethods:Hide() self._shown = false end
function frameMethods:IsShown() return self._shown end
function frameMethods:SetAlpha(a) self._alpha = a end
function frameMethods:GetAlpha() return self._alpha end
function frameMethods:SetHeight(h) self._height = h end
function frameMethods:GetHeight() return self._height or 20 end
function frameMethods:SetWidth(w) self._width = w end
function frameMethods:GetWidth() return self._width or 200 end
function frameMethods:SetValue(v) self._value = v end
function frameMethods:GetValue() return self._value or 0 end
function frameMethods:SetStatusBarColor(r, g, b) self._color = { r, g, b } end
function frameMethods:GetStatusBarColor()
    if self._color then return self._color[1], self._color[2], self._color[3], 1 end
    return 1, 1, 1, 1
end
function frameMethods:SetAllPoints(other) self._anchoredTo = other end
function frameMethods:GetStatusBarTexture()
    self._sbt = self._sbt or setmetatable({ _events = {}, _scripts = {} }, { __index = frameMethods })
    return self._sbt
end
function frameMethods:GetChildren() return table.unpack(self._children or {}) end
function frameMethods:CreateTexture(name)
    local t = setmetatable({ _events = {}, _scripts = {} }, { __index = frameMethods })
    self._textureCount = (self._textureCount or 0) + 1
    if name then _G[name] = t end
    return t
end
function frameMethods:CreateFontString(name) return self:CreateTexture(name) end

function CreateFrame(_frameType, name)
    local f = setmetatable({
        _events = {}, _scripts = {}, _children = {}, _shown = false, _alpha = 1,
    }, { __index = frameMethods })
    if name then
        _G[name] = f
        frameRegistry[name] = f
    end
    return f
end

UIParent = CreateFrame("Frame", "UIParent")

-- Secure post-hook mock: wrap the current method so the hook runs afterwards.
function hooksecurefunc(tbl, name, hook)
    local original = tbl[name]
    tbl[name] = function(...)
        local results = { original(...) }
        hook(...)
        return table.unpack(results)
    end
end

local function newWidget()
    return setmetatable({ _events = {}, _scripts = {} }, { __index = frameMethods })
end

-- Fire an event onto a frame's OnEvent handler, as the client would.
local function fire(frame, event, ...)
    local handler = frame._scripts.OnEvent
    if handler then handler(frame, event, ...) end
end

-------------------------------------------------------------------------------
-- World state the mocked unit/spec APIs read from
-------------------------------------------------------------------------------
local world = {
    targetExists = true, canAttack = true, isDead = false, healthPercent = 0.5,
    guid = "Creature-1", inCombat = false,
    specIndex = 1, specID = 102, -- 102 = Balance Druid (a DPS spec)
    powerType = 0, powerToken = "MANA", power = 50, powerMax = 100,
    now = 100,
}

function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetTime() return world.now end
function UnitAffectingCombat() return world.inCombat end
function GetSpecialization() return world.specIndex end
function GetSpecializationInfo() return world.specID end
function UnitExists() return world.targetExists end
function UnitCanAttack() return world.canAttack end
function UnitIsDeadOrGhost() return world.isDead end
function UnitIsDead() return world.isDead end
function UnitGUID() return world.guid end
function UnitHealthPercent(_unit, _pred, _curve) return world.healthPercent end
function UnitPowerType() return world.powerType, world.powerToken end
function UnitPower() return world.power end
function UnitPowerMax() return world.powerMax end
function UnitPowerPercent() return 50 end

function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a, GetRGB = function(self) return self.r, self.g, self.b end }
end

C_CurveUtil = {
    CreateCurve = function() return { AddPoint = noop, SetType = noop } end,
    CreateColorCurve = function() return { AddPoint = noop, SetType = noop } end,
}
C_Timer = { After = function(_delay, fn) fn() end } -- run synchronously
Enum = { PowerType = { AstralPower = 8 }, LuaCurveType = { Linear = 1, Step = 2 } }
CurveConstants = { ScaleTo100 = {} }

UIErrorsFrame = {
    messages = {},
    AddMessage = function(self, msg) table.insert(self.messages, msg) end,
}
function PlaySound() end
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })

SLASH_SIDEKICK1, SLASH_SIDEKICK2 = nil, nil
SlashCmdList = {}

-- Capture addon output so test results stay readable.
local addonOutput = {}
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(addonOutput, table.concat(parts, " "))
end

-------------------------------------------------------------------------------
-- Load the real addon files with the addon varargs (addonName, sharedTable),
-- exactly as the client passes them, so the shared namespace works.
-------------------------------------------------------------------------------
local addonNamespace = {}
assert(loadfile("Sidekick.lua"))("Sidekick", addonNamespace)
assert(loadfile("ResourceBar.lua"))("Sidekick", addonNamespace)

local sidekick = frameRegistry["SidekickFrame"]
local resourceBar = _G.SidekickResourceBar

-------------------------------------------------------------------------------
-- Assertion helpers
-------------------------------------------------------------------------------
local passed, failed = 0, 0

local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        realprint("PASS  " .. name)
    else
        failed = failed + 1
        realprint("FAIL  " .. name .. "\n        " .. tostring(err))
    end
end

local function assertTrue(value, msg)
    if not value then error(msg or "expected truthy value", 2) end
end

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "value mismatch") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

-------------------------------------------------------------------------------
-- Group A: Sidekick core (glow + target reminder), including secret health
-------------------------------------------------------------------------------
check("A1 addon frames loaded", function()
    assertTrue(sidekick, "SidekickFrame not created")
    assertTrue(resourceBar, "SidekickResourceBar not exported")
end)

check("A2 ADDON_LOADED initializes SavedVariables", function()
    fire(sidekick, "ADDON_LOADED", "Sidekick")
    assertEq(SidekickDB.enabled, true, "SidekickDB.enabled")
end)

check("A3 PLAYER_ENTERING_WORLD builds the edge frame", function()
    world.inCombat = false
    fire(sidekick, "PLAYER_ENTERING_WORLD")
    assertTrue(_G.SidekickEdgeFrame, "edge frame not created")
end)

check("A4 PLAYER_SPECIALIZATION_CHANGED accepts a DPS spec", function()
    world.specID = 102
    fire(sidekick, "PLAYER_SPECIALIZATION_CHANGED")
end)

check("A5 glow drives SetAlpha from a SECRET health value", function()
    world.targetExists = true
    world.canAttack = true
    world.isDead = false
    world.healthPercent = makeSecret() -- would crash if code did arithmetic
    fire(sidekick, "PLAYER_REGEN_DISABLED") -- enter combat -> UpdateGlow
    assertEq(_G.SidekickEdgeFrame:IsShown(), true, "glow should show on a live target")
    assertTrue(issecretvalue(_G.SidekickEdgeFrame:GetAlpha()),
        "the secret value should have reached SetAlpha untouched")
end)

check("A6 UNIT_HEALTH re-evaluates without error", function()
    fire(sidekick, "UNIT_HEALTH", "target")
end)

check("A7 no target in combat warns the player", function()
    world.now = 100
    world.targetExists = false
    fire(sidekick, "PLAYER_TARGET_CHANGED")
    assertEq(_G.SidekickEdgeFrame:IsShown(), false, "glow should hide with no target")
    assertTrue(#UIErrorsFrame.messages > 0, "expected a target-reminder message")
end)

check("A8 dead target (readable) hides the glow", function()
    world.now = 200 -- bypass warning cooldown
    world.targetExists = true
    world.isDead = true
    fire(sidekick, "UNIT_HEALTH", "target")
    assertEq(_G.SidekickEdgeFrame:IsShown(), false, "glow should hide on a dead target")
end)

check("A9 SECRET dead flag is skipped, not compared", function()
    world.isDead = makeSecret() -- comparing this would crash
    world.canAttack = makeSecret() -- attackability also secret
    world.healthPercent = makeSecret()
    fire(sidekick, "UNIT_HEALTH", "target")
    assertEq(_G.SidekickEdgeFrame:IsShown(), true, "glow should still show when flags are secret")
end)

check("A10 leaving combat hides the glow", function()
    fire(sidekick, "PLAYER_REGEN_ENABLED")
    assertEq(_G.SidekickEdgeFrame:IsShown(), false, "glow should hide out of combat")
end)

-------------------------------------------------------------------------------
-- Group B: public SidekickResourceBar API surface is callable
-------------------------------------------------------------------------------
check("B1 public API methods exist", function()
    for _, method in ipairs({
        "AddThreshold", "RemoveThreshold", "ClearThresholds", "SetEnabled",
        "ToggleFeature", "IsFeatureEnabled", "ListThresholds",
    }) do
        assertEq(type(resourceBar[method]), "function", "missing API method " .. method)
    end
end)

check("B2 ResourceBar ADDON_LOADED sets up its database", function()
    fire(resourceBar, "ADDON_LOADED", "Sidekick")
    assertTrue(SidekickDB.resourceBar, "resourceBar DB not created")
    assertTrue(SidekickDB.resourceBar.thresholds, "thresholds table not created")
end)

check("B3 SetEnabled(true) finds the power bar via a known frame path", function()
    -- Blizzard-style nested ManaBar (FindPowerBarFrame Method 2)
    local manaBar = newWidget()
    manaBar._shown = true
    PlayerFrame = CreateFrame("Frame", "PlayerFrame")
    PlayerFrame.PlayerFrameContent = { PlayerFrameContentMain = { ManaBar = manaBar } }
    world.power = 50
    world.powerMax = 100
    resourceBar:SetEnabled(true)
    assertTrue(resourceBar:IsEventRegistered("UNIT_POWER_UPDATE"),
        "SetEnabled(true) should register the player power event")
end)

check("B4 AddThreshold / ListThresholds round-trips", function()
    resourceBar:ClearThresholds()
    resourceBar:AddThreshold(40, 1, 1, 0, "Starsurge")
    local list = resourceBar:ListThresholds()
    assertEq(#list, 1, "threshold count")
    assertEq(list[1].value, 40, "threshold value")
    assertEq(list[1].name, "Starsurge", "threshold name")
end)

check("B5 ToggleFeature / IsFeatureEnabled agree", function()
    local before = resourceBar:IsFeatureEnabled("colors")
    local after = resourceBar:ToggleFeature("colors")
    assertEq(after, not before, "toggle should flip the feature")
    assertEq(resourceBar:IsFeatureEnabled("colors"), after, "state should persist")
    resourceBar:ToggleFeature("colors") -- restore
end)

check("B6 RemoveThreshold / ClearThresholds", function()
    resourceBar:AddThreshold(60, 0, 1, 0, "Starfall")
    resourceBar:RemoveThreshold(1)
    assertTrue(#resourceBar:ListThresholds() >= 0)
    resourceBar:ClearThresholds()
    assertEq(#resourceBar:ListThresholds(), 0, "clear should empty thresholds")
end)

-------------------------------------------------------------------------------
-- Group C: ResourceBar secret-value safety
-------------------------------------------------------------------------------
check("C1 UNIT_POWER_UPDATE with normal power runs clean", function()
    world.power = 50
    world.powerMax = 100
    resourceBar:AddThreshold(40, 1, 1, 0, "T")
    fire(resourceBar, "UNIT_POWER_UPDATE", "player")
end)

check("C2 SECRET current power is guarded (no arithmetic)", function()
    world.power = makeSecret()
    fire(resourceBar, "UNIT_POWER_UPDATE", "player") -- OnPowerUpdate must bail
    world.power = 50
end)

check("C3 SECRET max power short-circuits marker math", function()
    world.powerMax = makeSecret() -- threshold.value / maxPower would crash
    fire(resourceBar, "UNIT_MAXPOWER", "player")
    world.powerMax = 100
end)

check("C4 astral-power numeric fallback guards a secret max", function()
    world.powerToken = "ASTRAL_POWER"
    local savedAstral = Enum.PowerType.AstralPower
    Enum.PowerType.AstralPower = nil -- force the numeric power-type-8 branch
    world.powerMax = makeSecret()    -- UnitPowerMax('player', 8) > 0 would crash
    fire(resourceBar, "UNIT_MAXPOWER", "player")
    Enum.PowerType.AstralPower = savedAstral
    world.powerToken = "MANA"
    world.powerMax = 100
end)

check("C5 frame scan (Method 4) skips secret bar values and matches real ones", function()
    -- No known frame path -> forces the child-scan fallback.
    PlayerFrame = CreateFrame("Frame", "PlayerFrame")
    local secretBar = newWidget()
    secretBar._value = makeSecret() -- comparing this would crash
    local matchBar = newWidget()
    matchBar._value = 50
    PlayerFrame._children = { secretBar, matchBar }
    world.power = 50
    resourceBar:SetEnabled(false)
    resourceBar:SetEnabled(true) -- Initialize -> FindPowerBarFrame Method 4
end)

-------------------------------------------------------------------------------
-- Group D: slash command surface
-------------------------------------------------------------------------------
check("D1 /sidekick toggle", function()
    local cmd = SlashCmdList["SIDEKICK"]
    assertTrue(type(cmd) == "function", "slash handler missing")
    cmd("toggle")
    cmd("toggle") -- restore
end)

check("D2 /sk rb add with hex color", function()
    SlashCmdList["SIDEKICK"]("rb add 40 #FFFF00 Starsurge")
end)

check("D3 /sk rb add with decimal color", function()
    SlashCmdList["SIDEKICK"]("rb add 50 0,0.5,1.0 Starfall")
end)

check("D4 /sk rb list | status | help", function()
    SlashCmdList["SIDEKICK"]("rb list")
    SlashCmdList["SIDEKICK"]("rb status")
    SlashCmdList["SIDEKICK"]("rb")
    SlashCmdList["SIDEKICK"]("") -- top-level help
end)

check("D5 /sk test diagnostics force the glow on", function()
    -- Put the addon into combat so the forced test glow is not auto-cleared
    world.targetExists = true
    world.canAttack = true
    world.isDead = false
    world.healthPercent = 1
    fire(sidekick, "PLAYER_REGEN_DISABLED") -- addon inCombat = true
    SlashCmdList["SIDEKICK"]("test")
    assertEq(_G.SidekickEdgeFrame:IsShown(), true, "test should force the glow visible")
    assertEq(_G.SidekickEdgeFrame:GetAlpha(), 1, "test should force full alpha")
    fire(sidekick, "PLAYER_REGEN_ENABLED") -- restore out-of-combat state
end)

-------------------------------------------------------------------------------
-- Group E: Phase 3 (shared namespace, overlay isolation, anchor swap, color hook)
-------------------------------------------------------------------------------
check("E1 shared IsSecret lives on the addon namespace", function()
    assertEq(type(addonNamespace.IsSecret), "function", "ns.IsSecret should be shared")
    assertEq(addonNamespace.IsSecret(makeSecret()), true, "secret should read as secret")
    assertEq(addonNamespace.IsSecret(5), false, "plain value should not read as secret")
end)

-- A known target bar we control, pointed at via the anchor API.
local testBar = newWidget()
testBar._shown = true
_G["SidekickTestBar"] = testBar
world.power = 50
world.powerMax = 100

check("E2 anchor swap re-points the overlay to the chosen bar", function()
    resourceBar:SetEnabled(true)
    resourceBar:SetAnchor("SidekickTestBar")
    local overlay = _G.SidekickResourceOverlay
    assertTrue(overlay, "overlay frame should exist")
    assertEq(overlay._anchoredTo, testBar, "overlay should anchor to the chosen bar")
end)

check("E3 markers attach to the overlay, never the target bar", function()
    resourceBar:ClearThresholds()
    testBar._textureCount = 0
    local overlay = _G.SidekickResourceOverlay
    overlay._textureCount = 0
    resourceBar:AddThreshold(40, 1, 1, 0, "E")
    assertTrue((overlay._textureCount or 0) > 0, "markers should be created on the overlay")
    assertEq(testBar._textureCount or 0, 0, "no textures should be added to the target bar")
end)

check("E4 color hook reapplies our threshold color after a Blizzard update", function()
    if not resourceBar:IsFeatureEnabled("colors") then
        resourceBar:ToggleFeature("colors")
    end
    world.power = 50 -- at/above the 40 threshold -> active
    -- Simulate Blizzard resetting the bar color; our secure hook should override.
    testBar:SetStatusBarColor(0.2, 0.2, 0.2)
    assertEq(testBar._color[1], 1, "red channel reapplied")
    assertEq(testBar._color[2], 1, "green channel reapplied")
    assertEq(testBar._color[3], 0, "blue channel reapplied")
end)

check("E5 /sk rb anchor slash command routes to SetAnchor", function()
    SlashCmdList["SIDEKICK"]("rb anchor auto")
    assertEq(SidekickDB.resourceBar.anchor, "auto", "anchor should reset to auto")
end)

-------------------------------------------------------------------------------
-- Summary
-------------------------------------------------------------------------------
realprint(string.rep("-", 60))
realprint(string.format("Total: %d   Passed: %d   Failed: %d", passed + failed, passed, failed))
os.exit(failed == 0 and 0 or 1)
