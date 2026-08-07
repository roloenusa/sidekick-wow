-- Sidekick: Alerts DPS players to target enemies and shows low health indicators
-- Version: 3.0.0
-- Compatible with: WoW 12.0.x (Midnight) and later
--
-- Midnight (Patch 12.0) introduced "Secret Values": in restricted combat the
-- game hands addons opaque values for a unit's health that cannot be read,
-- compared, or used in arithmetic. Any such operation is an immediate Lua error.
-- Sidekick therefore never inspects target health. Instead it feeds the health
-- percent through a Blizzard curve object that outputs an alpha value, and pipes
-- that alpha straight into the glow frame. The glow reflects the fight without
-- the addon ever "knowing" the number. This mirrors the pattern used by Cell.
-- See: https://warcraft.wiki.gg/wiki/Secret_Values

-------------------------------------------------------------------------------
-- Addon Declaration
-------------------------------------------------------------------------------
local ADDON_NAME = "Sidekick"
local Sidekick = CreateFrame("Frame", "SidekickFrame")
Sidekick:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

-------------------------------------------------------------------------------
-- Local State
-------------------------------------------------------------------------------
local edgeFrame = nil
local edgeTextures = {}  -- Store texture references
local lowHealthCurve = nil  -- CurveObject mapping health percent -> glow alpha
local lastWarningTime = 0
local isDPSSpec = false
local inCombat = false
local isEnabled = false
local addonLoaded = false

-------------------------------------------------------------------------------
-- Configuration Constants
-------------------------------------------------------------------------------
local WARNING_COOLDOWN = 3        -- seconds between warnings
local EDGE_GRADIENT_SIZE = 120    -- Size of edge gradients in pixels

-- Health thresholds as FRACTIONS (0.0 - 1.0), matching the curve range used by
-- Cell's Midnight code. The glow is fully on at or below HEALTH_SHOW_THRESHOLD
-- and fades out to nothing by HEALTH_HIDE_THRESHOLD.
--
-- NOTE: If UnitHealthPercent turns out to feed the curve a 0-100 value instead
-- of 0-1, the glow will trigger at the wrong point. If that happens in-game,
-- change these two lines to 10 and 12.
local HEALTH_SHOW_THRESHOLD = 0.10
local HEALTH_HIDE_THRESHOLD = 0.12

-- DPS spec IDs. These are stable identifiers and unaffected by Secret Values.
local DPS_SPECS = {
    -- Druid
    [102] = true, -- Balance
    [103] = true, -- Feral
    -- Death Knight
    [251] = true, -- Frost
    [252] = true, -- Unholy
    -- Demon Hunter
    [577] = true, -- Havoc
    -- Evoker
    [1467] = true, -- Devastation
    [1473] = true, -- Augmentation
    -- Hunter (all specs)
    [253] = true, -- Beast Mastery
    [254] = true, -- Marksmanship
    [255] = true, -- Survival
    -- Mage (all specs)
    [62] = true, -- Arcane
    [63] = true, -- Fire
    [64] = true, -- Frost
    -- Monk
    [269] = true, -- Windwalker
    -- Paladin
    [70] = true, -- Retribution
    -- Priest
    [258] = true, -- Shadow
    -- Rogue (all specs)
    [259] = true, -- Assassination
    [260] = true, -- Outlaw
    [261] = true, -- Subtlety
    -- Shaman
    [262] = true, -- Elemental
    [263] = true, -- Enhancement
    -- Warlock (all specs)
    [265] = true, -- Affliction
    [266] = true, -- Demonology
    [267] = true, -- Destruction
    -- Warrior
    [71] = true, -- Arms
    [72] = true, -- Fury
}

-------------------------------------------------------------------------------
-- Secret Value Helpers
-------------------------------------------------------------------------------

-- True if the value is a Midnight "secret value" that we may not inspect.
-- issecretvalue itself is safe to call on any value and returns a plain boolean.
local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- True if the curve-based health display API is available (Midnight 12.0+).
local function HasHealthCurveAPI()
    return C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent and true or false
end

-------------------------------------------------------------------------------
-- UI Creation (frames built in Lua, BigWigs style)
-------------------------------------------------------------------------------

-- Build the curve that maps health percent to glow alpha. Output is 1.0 at or
-- below the show threshold and ramps to 0.0 by the hide threshold, giving a
-- smooth fade with no flicker and no need for the addon to read the value.
local function BuildLowHealthCurve()
    if not HasHealthCurveAPI() then
        return nil
    end

    local curve = C_CurveUtil.CreateCurve()
    curve:AddPoint(0.0, 1.0)                     -- near death: full glow
    curve:AddPoint(HEALTH_SHOW_THRESHOLD, 1.0)   -- at threshold: full glow
    curve:AddPoint(HEALTH_HIDE_THRESHOLD, 0.0)   -- just above: fading out
    curve:AddPoint(1.0, 0.0)                      -- healthy: no glow
    return curve
end

-- Create the edge glow frame programmatically
local function CreateEdgeFrame()
    edgeFrame = CreateFrame("Frame", "SidekickEdgeFrame", UIParent)
    edgeFrame:SetFrameStrata("HIGH")
    edgeFrame:SetFrameLevel(100)
    edgeFrame:SetSize(1, 1)
    edgeFrame:SetPoint("CENTER", UIParent, "CENTER")
    edgeFrame:SetAlpha(0)
    edgeFrame:Hide()

    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()

    -- Gradient colors as ColorMixin objects (correct since Dragonflight 10.0)
    local orangeStart = CreateColor(1.0, 0.5, 0.0, 0.7)
    local orangeEnd = CreateColor(1.0, 0.5, 0.0, 0.0)

    local topEdge = edgeFrame:CreateTexture("SidekickEdgeFrameTopEdge", "BACKGROUND")
    topEdge:SetSize(screenWidth, EDGE_GRADIENT_SIZE)
    topEdge:SetPoint("TOP", UIParent, "TOP", 0, 0)
    topEdge:SetGradient("VERTICAL", orangeStart, orangeEnd)
    edgeTextures.top = topEdge

    local bottomEdge = edgeFrame:CreateTexture("SidekickEdgeFrameBottomEdge", "BACKGROUND")
    bottomEdge:SetSize(screenWidth, EDGE_GRADIENT_SIZE)
    bottomEdge:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    bottomEdge:SetGradient("VERTICAL", orangeEnd, orangeStart)
    edgeTextures.bottom = bottomEdge

    local leftEdge = edgeFrame:CreateTexture("SidekickEdgeFrameLeftEdge", "BACKGROUND")
    leftEdge:SetSize(EDGE_GRADIENT_SIZE, screenHeight)
    leftEdge:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
    leftEdge:SetGradient("HORIZONTAL", orangeStart, orangeEnd)
    edgeTextures.left = leftEdge

    local rightEdge = edgeFrame:CreateTexture("SidekickEdgeFrameRightEdge", "BACKGROUND")
    rightEdge:SetSize(EDGE_GRADIENT_SIZE, screenHeight)
    rightEdge:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)
    rightEdge:SetGradient("HORIZONTAL", orangeEnd, orangeStart)
    edgeTextures.right = rightEdge

    lowHealthCurve = BuildLowHealthCurve()

    return edgeFrame
end

-- Update edge frame size on screen resolution changes
local function UpdateEdgeFrameSize()
    if not edgeFrame then return end

    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()

    if edgeTextures.top then
        edgeTextures.top:SetSize(screenWidth, EDGE_GRADIENT_SIZE)
    end
    if edgeTextures.bottom then
        edgeTextures.bottom:SetSize(screenWidth, EDGE_GRADIENT_SIZE)
    end
    if edgeTextures.left then
        edgeTextures.left:SetSize(EDGE_GRADIENT_SIZE, screenHeight)
    end
    if edgeTextures.right then
        edgeTextures.right:SetSize(EDGE_GRADIENT_SIZE, screenHeight)
    end
end

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------

-- Safe check if player is a DPS spec
local function UpdateSpecStatus()
    local specIndex = GetSpecialization()
    if not specIndex then
        isDPSSpec = false
        return
    end

    local specID = GetSpecializationInfo(specIndex)
    isDPSSpec = DPS_SPECS[specID] or false
end

-- Show warning message and play sound (with cooldown)
local function ShowTargetWarning()
    local currentTime = GetTime()
    if currentTime - lastWarningTime < WARNING_COOLDOWN then
        return
    end

    lastWarningTime = currentTime

    UIErrorsFrame:AddMessage("Target an enemy unit!", 1.0, 0.2, 0.2, 1.0, 5)
    PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST)
end

-- Hide the low health edge glow
local function HideGlow()
    if edgeFrame then
        edgeFrame:Hide()
    end
end

-- Update the glow. The addon only branches on facts it is allowed to know
-- (combat state, spec, target existence, and attackability when readable).
-- The actual low-health decision is delegated entirely to the curve, so a
-- secret health value is never inspected.
local function UpdateGlow()
    if not edgeFrame then return end

    -- If the curve API is missing (pre-Midnight client), disable the glow
    -- rather than fall back to the old, now-illegal, health arithmetic.
    if not (lowHealthCurve and UnitHealthPercent) then
        HideGlow()
        return
    end

    if not (inCombat and isEnabled and isDPSSpec) then
        HideGlow()
        return
    end

    -- In combat with nothing targeted: remind the player to grab an enemy.
    if not UnitExists("target") then
        HideGlow()
        ShowTargetWarning()
        return
    end

    -- If we can read attackability (not secret) and the target is friendly,
    -- there is nothing to glow about; nudge the player instead.
    local canAttack = UnitCanAttack("player", "target")
    if not IsSecret(canAttack) and not canAttack then
        HideGlow()
        ShowTargetWarning()
        return
    end

    -- A dead target should never glow. UnitIsDead may be secret in restricted
    -- content; only act on it when we can actually read it.
    local isDead = UnitIsDead("target")
    if not IsSecret(isDead) and isDead then
        HideGlow()
        ShowTargetWarning()
        return
    end

    -- Drive the glow alpha from the (possibly secret) health percent via the
    -- curve. SetAlpha accepts secret values; we never see the number ourselves.
    edgeFrame:Show()
    edgeFrame:SetAlpha(UnitHealthPercent("target", false, lowHealthCurve))
end

-------------------------------------------------------------------------------
-- Event Registration Management (register combat events only during combat)
-------------------------------------------------------------------------------

local function RegisterCombatEvents()
    if not isEnabled or not isDPSSpec then
        return
    end

    Sidekick:RegisterEvent("PLAYER_TARGET_CHANGED")
    Sidekick:RegisterUnitEvent("UNIT_HEALTH", "target")
    Sidekick:RegisterEvent("UNIT_DIED")
end

local function UnregisterCombatEvents()
    Sidekick:UnregisterEvent("PLAYER_TARGET_CHANGED")
    Sidekick:UnregisterEvent("UNIT_HEALTH")
    Sidekick:UnregisterEvent("UNIT_DIED")
end

local function UpdateEventRegistration()
    if not addonLoaded then
        return
    end

    if inCombat and isEnabled and isDPSSpec then
        RegisterCombatEvents()
    else
        UnregisterCombatEvents()
    end
end

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

function Sidekick:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then
        return
    end

    if not SidekickDB then
        SidekickDB = {
            enabled = true
        }
    end

    if type(SidekickDB.enabled) ~= "boolean" then
        SidekickDB.enabled = true
    end

    isEnabled = SidekickDB.enabled
    addonLoaded = true

    print("|cFF00FF00Sidekick loaded!|r Type /sidekick for options.")

    self:UnregisterEvent("ADDON_LOADED")
end

function Sidekick:PLAYER_ENTERING_WORLD()
    if not edgeFrame then
        CreateEdgeFrame()
    end

    UpdateEdgeFrameSize()

    UpdateSpecStatus()
    inCombat = UnitAffectingCombat("player") or false
    UpdateEventRegistration()
end

function Sidekick:PLAYER_SPECIALIZATION_CHANGED()
    UpdateSpecStatus()
    UpdateEventRegistration()

    if not isDPSSpec then
        HideGlow()
    end
end

function Sidekick:PLAYER_REGEN_DISABLED()
    -- Entered combat
    inCombat = true
    UpdateEventRegistration()
    UpdateGlow()
end

function Sidekick:PLAYER_REGEN_ENABLED()
    -- Left combat
    inCombat = false
    UpdateEventRegistration()
    HideGlow()
end

function Sidekick:PLAYER_TARGET_CHANGED()
    if not isEnabled then
        return
    end
    UpdateGlow()
end

function Sidekick:UNIT_HEALTH(unit)
    if unit ~= "target" or not isEnabled then
        return
    end
    UpdateGlow()
end

-- UNIT_DIED replaces the old COMBAT_LOG_EVENT_UNFILTERED path, which now errors
-- when registered under Midnight. The payload is the GUID of the unit that died.
function Sidekick:UNIT_DIED(unitGUID)
    if not isEnabled then
        return
    end

    local targetGUID = UnitGUID("target")

    -- GUIDs can be secret in restricted content; do not compare them if so.
    -- UNIT_HEALTH / PLAYER_TARGET_CHANGED will still correct the glow.
    if IsSecret(unitGUID) or IsSecret(targetGUID) then
        return
    end

    if targetGUID and unitGUID == targetGUID then
        HideGlow()
        if inCombat and isDPSSpec then
            ShowTargetWarning()
        end
    end
end

function Sidekick:UI_SCALE_CHANGED()
    UpdateEdgeFrameSize()
end

function Sidekick:DISPLAY_SIZE_CHANGED()
    UpdateEdgeFrameSize()
end

-------------------------------------------------------------------------------
-- Slash Commands
-------------------------------------------------------------------------------

-- Helper to parse color from hex or RGB
local function ParseColor(colorStr)
    -- Try hex format first (#RRGGBB or RRGGBB)
    local hex = colorStr:match("^#?(%x%x%x%x%x%x)$")
    if hex then
        local r = tonumber(hex:sub(1,2), 16) / 255
        local g = tonumber(hex:sub(3,4), 16) / 255
        local b = tonumber(hex:sub(5,6), 16) / 255
        return r, g, b
    end

    -- Try decimal RGB format (r,g,b or r g b)
    local r, g, b = colorStr:match("(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)")
    if r and g and b then
        r, g, b = tonumber(r), tonumber(g), tonumber(b)
        -- If values are > 1, assume 0-255 range, otherwise 0-1
        if r > 1 or g > 1 or b > 1 then
            r, g, b = r/255, g/255, b/255
        end
        return r, g, b
    end

    return nil
end

SLASH_SIDEKICK1 = "/sidekick"
SLASH_SIDEKICK2 = "/sk"
SlashCmdList["SIDEKICK"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "toggle" then
        SidekickDB.enabled = not SidekickDB.enabled
        isEnabled = SidekickDB.enabled

        if isEnabled then
            print("|cFF00FF00Sidekick: Enabled|r")
        else
            print("|cFFFF0000Sidekick: Disabled|r")
            HideGlow()
        end
        UpdateEventRegistration()

    -- Resource Bar Commands
    elseif cmd == "rb" or cmd == "resourcebar" then
        local subcmd = args[2] and args[2]:lower() or ""

        if subcmd == "on" or subcmd == "enable" then
            if SidekickResourceBar then
                SidekickResourceBar:SetEnabled(true)
                print("|cFF00FF00Resource Bar customization: Enabled|r")
            else
                print("|cFFFF0000Resource Bar module not loaded|r")
            end

        elseif subcmd == "off" or subcmd == "disable" then
            if SidekickResourceBar then
                SidekickResourceBar:SetEnabled(false)
                print("|cFFFF0000Resource Bar customization: Disabled|r")
            else
                print("|cFFFF0000Resource Bar module not loaded|r")
            end

        elseif subcmd == "add" then
            -- /sk rb add <value> <color> [name]
            local value = tonumber(args[3])
            local colorStr = args[4]
            local name = args[5] or ""

            if not value or not colorStr then
                print("|cFFFF0000Usage: /sk rb add <value> <color> [name]|r")
                print("|cFFFFFF00Example: /sk rb add 40 #FFFF00 Starsurge|r")
                print("|cFFFFFF00Example: /sk rb add 50 0,0.5,1.0 Starfall|r")
                return
            end

            local r, g, b = ParseColor(colorStr)
            if not r then
                print("|cFFFF0000Invalid color format. Use #RRGGBB or r,g,b|r")
                return
            end

            if SidekickResourceBar then
                SidekickResourceBar:AddThreshold(value, r, g, b, name)
                print(string.format("|cFF00FF00Added threshold: %s at %d|r", name ~= "" and name or "Unnamed", value))
            else
                print("|cFFFF0000Resource Bar module not loaded|r")
            end

        elseif subcmd == "remove" or subcmd == "delete" then
            local index = tonumber(args[3])
            if not index then
                print("|cFFFF0000Usage: /sk rb remove <index>|r")
                return
            end

            if SidekickResourceBar then
                SidekickResourceBar:RemoveThreshold(index)
                print("|cFF00FF00Threshold removed|r")
            else
                print("|cFFFF0000Resource Bar module not loaded|r")
            end

        elseif subcmd == "clear" then
            if SidekickResourceBar then
                SidekickResourceBar:ClearThresholds()
                print("|cFF00FF00All thresholds cleared|r")
            else
                print("|cFFFF0000Resource Bar module not loaded|r")
            end

        elseif subcmd == "list" then
            if not SidekickResourceBar then
                print("|cFFFF0000Resource Bar module not loaded|r")
                return
            end

            local thresholds = SidekickResourceBar:ListThresholds()
            if not thresholds or #thresholds == 0 then
                print("|cFFFFFF00No thresholds configured|r")
            else
                print("|cFF00FF00Configured Thresholds:|r")
                for i, t in ipairs(thresholds) do
                    if t and t.color then
                        local colorHex = string.format("#%02X%02X%02X",
                            math.floor((t.color.r or 0) * 255),
                            math.floor((t.color.g or 0) * 255),
                            math.floor((t.color.b or 0) * 255))
                        print(string.format("|cFFFFFF00%d.|r %s (value: %d, color: %s)",
                            i, t.name or "Unnamed", t.value or 0, colorHex))
                    end
                end
            end

        elseif subcmd == "markers" then
            if SidekickResourceBar then
                local enabled = SidekickResourceBar:ToggleFeature("markers")
                print("|cFF00FF00Threshold Markers: " .. (enabled and "Enabled" or "Disabled") .. "|r")
            else
                print("|cFFFF0000Resource Bar module not loaded|r")
            end

        elseif subcmd == "colors" then
            if SidekickResourceBar then
                local enabled = SidekickResourceBar:ToggleFeature("colors")
                print("|cFF00FF00Dynamic Bar Colors: " .. (enabled and "Enabled" or "Disabled") .. "|r")
            else
                print("|cFFFF0000Resource Bar module not loaded|r")
            end

        elseif subcmd == "highlights" then
            if SidekickResourceBar then
                local enabled = SidekickResourceBar:ToggleFeature("highlights")
                print("|cFF00FF00Threshold Highlights: " .. (enabled and "Enabled" or "Disabled") .. "|r")
            else
                print("|cFFFF0000Resource Bar module not loaded|r")
            end

        elseif subcmd == "status" then
            if not SidekickResourceBar or not SidekickDB or not SidekickDB.resourceBar then
                print("|cFFFF0000Resource Bar module not loaded or not initialized|r")
                return
            end

            print("|cFF00FF00Resource Bar Status:|r")
            print("  Enabled: " .. (SidekickDB.resourceBar.enabled and "|cFF00FF00Yes|r" or "|cFFFF0000No|r"))
            print("  Markers: " .. (SidekickResourceBar:IsFeatureEnabled("markers") and "|cFF00FF00On|r" or "|cFFFF0000Off|r"))
            print("  Colors: " .. (SidekickResourceBar:IsFeatureEnabled("colors") and "|cFF00FF00On|r" or "|cFFFF0000Off|r"))
            print("  Highlights: " .. (SidekickResourceBar:IsFeatureEnabled("highlights") and "|cFF00FF00On|r" or "|cFFFF0000Off|r"))
            print("  Thresholds: " .. #SidekickDB.resourceBar.thresholds)

        else
            print("|cFF00FF00Resource Bar Commands:|r")
            print("/sk rb on|off - Enable/disable resource bar customization")
            print("/sk rb add <value> <color> [name] - Add threshold")
            print("/sk rb remove <index> - Remove threshold")
            print("/sk rb clear - Clear all thresholds")
            print("/sk rb list - List all thresholds")
            print("/sk rb markers - Toggle threshold markers")
            print("/sk rb colors - Toggle dynamic bar colors")
            print("/sk rb highlights - Toggle threshold highlights")
            print("/sk rb status - Show current configuration")
            print("|cFFFFFF00Color formats: #FFFF00 or 1.0,1.0,0.0 or 255,255,0|r")
        end

    else
        print("|cFF00FF00Sidekick Commands:|r")
        print("/sk toggle - Enable/disable target alerts")
        print("/sk rb - Resource bar customization (see /sk rb for details)")
    end
end

-------------------------------------------------------------------------------
-- Initialize Core Events
-------------------------------------------------------------------------------
Sidekick:RegisterEvent("ADDON_LOADED")
Sidekick:RegisterEvent("PLAYER_ENTERING_WORLD")
Sidekick:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
Sidekick:RegisterEvent("PLAYER_REGEN_DISABLED")
Sidekick:RegisterEvent("PLAYER_REGEN_ENABLED")
Sidekick:RegisterEvent("UI_SCALE_CHANGED")
Sidekick:RegisterEvent("DISPLAY_SIZE_CHANGED")
