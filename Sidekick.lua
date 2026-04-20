-- Sidekick: Alerts DPS players to target enemies and shows low health indicators
-- Version: 2.0.0
-- Compatible with: WoW 12.0.1+ (The War Within)
-- Rewritten using DBM/BigWigs patterns for robust event handling

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
local lastWarningTime = 0
local lowHealthShown = false
local isDPSSpec = false
local inCombat = false
local isEnabled = false
local addonLoaded = false

-------------------------------------------------------------------------------
-- Configuration Constants
-------------------------------------------------------------------------------
local WARNING_COOLDOWN = 3 -- seconds between warnings
local HEALTH_SHOW_THRESHOLD = 10  -- Show glow at or below this %
local HEALTH_HIDE_THRESHOLD = 12  -- Hide glow at or above this %

-- DPS spec role IDs (validated for WoW 12.0.1)
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

-- Check if target is a valid enemy
local function IsValidEnemy()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
end

-- Get target health percentage
local function GetTargetHealthPercent()
    if not UnitExists("target") then
        return 100
    end

    local health = UnitHealth("target")
    local maxHealth = UnitHealthMax("target")

    if not health or not maxHealth or maxHealth == 0 then
        return 100
    end

    return (health / maxHealth) * 100
end

-- Show warning message and play sound (with cooldown)
local function ShowTargetWarning()
    local currentTime = GetTime()
    if currentTime - lastWarningTime < WARNING_COOLDOWN then
        return
    end

    lastWarningTime = currentTime

    -- Display warning message
    UIErrorsFrame:AddMessage("Target an enemy unit!", 1.0, 0.2, 0.2, 1.0, 5)

    -- Play error sound
    PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST)
end

-- Show low health edge glow
local function ShowLowHealthGlow()
    if lowHealthShown or not edgeFrame then
        return
    end

    edgeFrame:Show()
    lowHealthShown = true
end

-- Hide low health edge glow
local function HideLowHealthGlow()
    if not lowHealthShown or not edgeFrame then
        return
    end

    edgeFrame:Hide()
    lowHealthShown = false
end

-- Check current state and update UI
local function CheckTargetState()
    -- Only trigger alerts when in combat and enabled
    if not inCombat or not isEnabled or not isDPSSpec then
        HideLowHealthGlow()
        return
    end

    -- Check for valid enemy target
    if not IsValidEnemy() then
        HideLowHealthGlow()
        -- Warn if targeting non-enemy while in combat
        if UnitExists("target") and not UnitIsDead("target") then
            ShowTargetWarning()
        end
        return
    end

    -- Check target health with hysteresis to prevent flickering
    local healthPercent = GetTargetHealthPercent()

    if lowHealthShown then
        -- Already showing - only hide if health rises above hide threshold
        if healthPercent >= HEALTH_HIDE_THRESHOLD then
            HideLowHealthGlow()
        end
    else
        -- Not showing - only show if health drops to or below show threshold
        if healthPercent <= HEALTH_SHOW_THRESHOLD then
            ShowLowHealthGlow()
        end
    end
end

-------------------------------------------------------------------------------
-- Event Registration Management (DBM-style)
-------------------------------------------------------------------------------

-- Register combat-specific events (only during combat)
local function RegisterCombatEvents()
    if not isEnabled or not isDPSSpec then
        return
    end

    Sidekick:RegisterEvent("PLAYER_TARGET_CHANGED")
    Sidekick:RegisterUnitEvent("UNIT_HEALTH", "target")
    Sidekick:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

-- Unregister combat-specific events
local function UnregisterCombatEvents()
    Sidekick:UnregisterEvent("PLAYER_TARGET_CHANGED")
    Sidekick:UnregisterEvent("UNIT_HEALTH")
    Sidekick:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

-- Update event registration based on state
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

    -- Initialize saved variables
    if not SidekickDB then
        SidekickDB = {
            enabled = true
        }
    end

    -- Ensure enabled is a boolean
    if type(SidekickDB.enabled) ~= "boolean" then
        SidekickDB.enabled = true
    end

    isEnabled = SidekickDB.enabled
    addonLoaded = true

    print("|cFF00FF00Sidekick loaded!|r Type /sidekick for options.")

    -- No need to listen for ADDON_LOADED anymore
    self:UnregisterEvent("ADDON_LOADED")
end

function Sidekick:PLAYER_ENTERING_WORLD()
    -- Get reference to edge frame
    edgeFrame = _G["SidekickEdgeFrame"]

    if not edgeFrame then
        print("|cFFFF0000Sidekick Error: Could not find edge frame|r")
        return
    end

    -- Set up textures to span full screen
    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()

    local topEdge = _G["SidekickEdgeFrameTopEdge"]
    local bottomEdge = _G["SidekickEdgeFrameBottomEdge"]
    local leftEdge = _G["SidekickEdgeFrameLeftEdge"]
    local rightEdge = _G["SidekickEdgeFrameRightEdge"]

    if topEdge then topEdge:SetWidth(screenWidth) end
    if bottomEdge then bottomEdge:SetWidth(screenWidth) end
    if leftEdge then leftEdge:SetHeight(screenHeight) end
    if rightEdge then rightEdge:SetHeight(screenHeight) end

    -- Set up gradients (WoW 12.0+ compatible with fallback)
    local orangeStart, orangeEnd

    if CreateColor then
        -- Modern API (11.0+, 12.0+)
        orangeStart = CreateColor(1.0, 0.5, 0.0, 0.7)
        orangeEnd = CreateColor(1.0, 0.5, 0.0, 0.0)
    else
        -- Fallback for potential API changes
        orangeStart = {r = 1.0, g = 0.5, b = 0.0, a = 0.7}
        orangeEnd = {r = 1.0, g = 0.5, b = 0.0, a = 0.0}
    end

    if topEdge then topEdge:SetGradient("VERTICAL", orangeStart, orangeEnd) end
    if bottomEdge then bottomEdge:SetGradient("VERTICAL", orangeEnd, orangeStart) end
    if leftEdge then leftEdge:SetGradient("HORIZONTAL", orangeStart, orangeEnd) end
    if rightEdge then rightEdge:SetGradient("HORIZONTAL", orangeEnd, orangeStart) end

    -- Update spec and combat status
    UpdateSpecStatus()
    inCombat = UnitAffectingCombat("player") or false
    UpdateEventRegistration()
end

function Sidekick:PLAYER_SPECIALIZATION_CHANGED()
    UpdateSpecStatus()
    UpdateEventRegistration()

    -- If we're no longer a DPS spec, clean up
    if not isDPSSpec then
        HideLowHealthGlow()
    end
end

function Sidekick:PLAYER_REGEN_DISABLED()
    -- Entered combat
    inCombat = true
    UpdateEventRegistration()
    CheckTargetState()
end

function Sidekick:PLAYER_REGEN_ENABLED()
    -- Left combat
    inCombat = false
    UpdateEventRegistration()
    HideLowHealthGlow()
end

function Sidekick:PLAYER_TARGET_CHANGED()
    if not isEnabled then
        return
    end
    CheckTargetState()
end

function Sidekick:UNIT_HEALTH(unit)
    if unit ~= "target" or not isEnabled then
        return
    end
    CheckTargetState()
end

function Sidekick:COMBAT_LOG_EVENT_UNFILTERED()
    if not isEnabled then
        return
    end

    local _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()

    -- Check for target death
    if subevent == "UNIT_DIED" then
        local targetGUID = UnitGUID("target")
        if targetGUID and destGUID == targetGUID then
            HideLowHealthGlow()
            -- If still in combat, warn to select new target
            if inCombat and isDPSSpec then
                ShowTargetWarning()
            end
        end
    end
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
            HideLowHealthGlow()
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
