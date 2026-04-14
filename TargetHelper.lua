-- Target Helper: Alerts DPS players to target enemies and shows low health indicators

local TargetHelper = CreateFrame("Frame")
local edgeFrame = nil
local lastWarningTime = 0
local WARNING_COOLDOWN = 3 -- seconds between warnings
local lowHealthShown = false
local isDPSSpec = false -- Cache DPS spec status
local inCombat = false -- Cache combat status

-- Health thresholds with hysteresis to prevent flickering
local HEALTH_SHOW_THRESHOLD = 10  -- Show glow when health drops to or below this
local HEALTH_HIDE_THRESHOLD = 12  -- Hide glow when health rises to or above this

-- DPS spec role IDs
local DPS_SPECS = {
    -- Druid
    [102] = true, -- Balance
    [103] = true, -- Feral
    -- Death Knight
    [250] = true, -- Blood (can be DPS in some contexts)
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

-- Update cached DPS spec status
local function UpdateSpecStatus()
    local specIndex = GetSpecialization()
    if not specIndex then
        isDPSSpec = false
        UpdateEventRegistration()
        return
    end

    local specID = GetSpecializationInfo(specIndex)
    isDPSSpec = DPS_SPECS[specID] or false
    UpdateEventRegistration()
end

-- Enable target tracking events
local function EnableTargetTracking()
    TargetHelper:RegisterEvent("PLAYER_TARGET_CHANGED")
    TargetHelper:RegisterUnitEvent("UNIT_HEALTH", "target")  -- Only fire for target unit
    TargetHelper:RegisterUnitEvent("UNIT_DIED", "target")    -- Only fire for target unit
end

-- Disable target tracking events
local function DisableTargetTracking()
    TargetHelper:UnregisterEvent("PLAYER_TARGET_CHANGED")
    TargetHelper:UnregisterEvent("UNIT_HEALTH")
    TargetHelper:UnregisterEvent("UNIT_DIED")
end

-- Update event registration based on current state
function UpdateEventRegistration()
    if not TargetHelperDB or not TargetHelperDB.enabled or not isDPSSpec then
        DisableTargetTracking()
    elseif inCombat then
        EnableTargetTracking()
    else
        -- When not in combat, keep target change events but unregister UNIT_HEALTH
        TargetHelper:RegisterEvent("PLAYER_TARGET_CHANGED")
        TargetHelper:RegisterUnitEvent("UNIT_DIED", "target")
        TargetHelper:UnregisterEvent("UNIT_HEALTH")
    end
end

-- Check if target is a valid enemy
local function IsValidEnemy()
    if not UnitExists("target") then
        return false
    end

    return UnitCanAttack("player", "target") and not UnitIsDead("target")
end

-- Get target health percentage
local function GetTargetHealthPercent()
    if not UnitExists("target") then
        return 100
    end

    local health = UnitHealth("target")
    local maxHealth = UnitHealthMax("target")

    if maxHealth == 0 then return 100 end

    return (health / maxHealth) * 100
end

-- Show warning message and play sound
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
    if not lowHealthShown and edgeFrame then
        edgeFrame:Show()
        lowHealthShown = true
    end
end

-- Hide low health edge glow
local function HideLowHealthGlow()
    if lowHealthShown and edgeFrame then
        edgeFrame:Hide()
        lowHealthShown = false
    end
end

-- Check current state and update UI
local function CheckTargetState()
    -- Only trigger alerts when in combat
    if not inCombat then
        HideLowHealthGlow()
        return
    end

    if not isDPSSpec then
        HideLowHealthGlow()
        return
    end

    -- Check for valid enemy target
    if not IsValidEnemy() then
        HideLowHealthGlow()
        if UnitExists("target") and not UnitIsDead("target") then
            -- Target exists but is not an enemy
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

-- Event handler
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "TargetHelper" then
            print("|cFF00FF00Target Helper loaded!|r Type /targethelper for options.")

            -- Initialize saved variables
            if not TargetHelperDB then
                TargetHelperDB = {
                    enabled = true
                }
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Get reference to edge frame
        edgeFrame = TargetHelperEdgeFrame

        -- Set up textures to span full screen width/height
        local screenWidth = GetScreenWidth()
        local screenHeight = GetScreenHeight()

        TargetHelperEdgeFrameTopEdge:SetWidth(screenWidth)
        TargetHelperEdgeFrameBottomEdge:SetWidth(screenWidth)
        TargetHelperEdgeFrameLeftEdge:SetHeight(screenHeight)
        TargetHelperEdgeFrameRightEdge:SetHeight(screenHeight)

        -- Update spec status when entering world/instances
        UpdateSpecStatus()

        -- Update combat status
        inCombat = UnitAffectingCombat("player")
        UpdateEventRegistration()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Update spec status when spec changes
        UpdateSpecStatus()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat
        inCombat = true
        UpdateEventRegistration()
        CheckTargetState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat
        inCombat = false
        UpdateEventRegistration()
        HideLowHealthGlow()
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Target changed - check new target
        if TargetHelperDB and TargetHelperDB.enabled then
            CheckTargetState()
        end
    elseif event == "UNIT_HEALTH" then
        -- Health changed - check if it's our target
        local unit = ...
        if unit == "target" and TargetHelperDB and TargetHelperDB.enabled then
            CheckTargetState()
        end
    elseif event == "UNIT_DIED" then
        -- Unit died - check if it's our target
        local unit = ...
        if unit == "target" then
            HideLowHealthGlow()

            -- If still in combat, warn to select new target
            if inCombat and isDPSSpec and TargetHelperDB and TargetHelperDB.enabled then
                ShowTargetWarning()
            end
        end
    end
end

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

-- Slash command handler
SLASH_TARGETHELPER1 = "/targethelper"
SLASH_TARGETHELPER2 = "/th"
SlashCmdList["TARGETHELPER"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "toggle" then
        TargetHelperDB.enabled = not TargetHelperDB.enabled
        if TargetHelperDB.enabled then
            print("|cFF00FF00Target Helper: Enabled|r")
        else
            print("|cFFFF0000Target Helper: Disabled|r")
            HideLowHealthGlow()
        end
        UpdateEventRegistration()

    -- Resource Bar Commands
    elseif cmd == "rb" or cmd == "resourcebar" then
        local subcmd = args[2] and args[2]:lower() or ""

        if subcmd == "on" or subcmd == "enable" then
            TargetHelperResourceBar:SetEnabled(true)
            print("|cFF00FF00Resource Bar customization: Enabled|r")

        elseif subcmd == "off" or subcmd == "disable" then
            TargetHelperResourceBar:SetEnabled(false)
            print("|cFFFF0000Resource Bar customization: Disabled|r")

        elseif subcmd == "add" then
            -- /th rb add <value> <color> [name]
            local value = tonumber(args[3])
            local colorStr = args[4]
            local name = args[5] or ""

            if not value or not colorStr then
                print("|cFFFF0000Usage: /th rb add <value> <color> [name]|r")
                print("|cFFFFFF00Example: /th rb add 40 #FFFF00 Starsurge|r")
                print("|cFFFFFF00Example: /th rb add 50 0,0.5,1.0 Starfall|r")
                return
            end

            local r, g, b = ParseColor(colorStr)
            if not r then
                print("|cFFFF0000Invalid color format. Use #RRGGBB or r,g,b|r")
                return
            end

            TargetHelperResourceBar:AddThreshold(value, r, g, b, name)
            print(string.format("|cFF00FF00Added threshold: %s at %d|r", name ~= "" and name or "Unnamed", value))

        elseif subcmd == "remove" or subcmd == "delete" then
            local index = tonumber(args[3])
            if not index then
                print("|cFFFF0000Usage: /th rb remove <index>|r")
                return
            end

            TargetHelperResourceBar:RemoveThreshold(index)
            print("|cFF00FF00Threshold removed|r")

        elseif subcmd == "clear" then
            TargetHelperResourceBar:ClearThresholds()
            print("|cFF00FF00All thresholds cleared|r")

        elseif subcmd == "list" then
            local thresholds = TargetHelperResourceBar:ListThresholds()
            if #thresholds == 0 then
                print("|cFFFFFF00No thresholds configured|r")
            else
                print("|cFF00FF00Configured Thresholds:|r")
                for i, t in ipairs(thresholds) do
                    local colorHex = string.format("#%02X%02X%02X",
                        math.floor(t.color.r * 255),
                        math.floor(t.color.g * 255),
                        math.floor(t.color.b * 255))
                    print(string.format("|cFFFFFF00%d.|r %s (value: %d, color: %s)",
                        i, t.name, t.value, colorHex))
                end
            end

        elseif subcmd == "markers" then
            local enabled = TargetHelperResourceBar:ToggleFeature("markers")
            print("|cFF00FF00Threshold Markers: " .. (enabled and "Enabled" or "Disabled") .. "|r")

        elseif subcmd == "colors" then
            local enabled = TargetHelperResourceBar:ToggleFeature("colors")
            print("|cFF00FF00Dynamic Bar Colors: " .. (enabled and "Enabled" or "Disabled") .. "|r")

        elseif subcmd == "highlights" then
            local enabled = TargetHelperResourceBar:ToggleFeature("highlights")
            print("|cFF00FF00Threshold Highlights: " .. (enabled and "Enabled" or "Disabled") .. "|r")

        elseif subcmd == "status" then
            print("|cFF00FF00Resource Bar Status:|r")
            print("  Enabled: " .. (TargetHelperDB.resourceBar.enabled and "|cFF00FF00Yes|r" or "|cFFFF0000No|r"))
            print("  Markers: " .. (TargetHelperResourceBar:IsFeatureEnabled("markers") and "|cFF00FF00On|r" or "|cFFFF0000Off|r"))
            print("  Colors: " .. (TargetHelperResourceBar:IsFeatureEnabled("colors") and "|cFF00FF00On|r" or "|cFFFF0000Off|r"))
            print("  Highlights: " .. (TargetHelperResourceBar:IsFeatureEnabled("highlights") and "|cFF00FF00On|r" or "|cFFFF0000Off|r"))
            print("  Thresholds: " .. #TargetHelperDB.resourceBar.thresholds)

        else
            print("|cFF00FF00Resource Bar Commands:|r")
            print("/th rb on|off - Enable/disable resource bar customization")
            print("/th rb add <value> <color> [name] - Add threshold")
            print("/th rb remove <index> - Remove threshold")
            print("/th rb clear - Clear all thresholds")
            print("/th rb list - List all thresholds")
            print("/th rb markers - Toggle threshold markers")
            print("/th rb colors - Toggle dynamic bar colors")
            print("/th rb highlights - Toggle threshold highlights")
            print("/th rb status - Show current configuration")
            print("|cFFFFFF00Color formats: #FFFF00 or 1.0,1.0,0.0 or 255,255,0|r")
        end

    else
        print("|cFF00FF00Target Helper Commands:|r")
        print("/th toggle - Enable/disable target alerts")
        print("/th rb - Resource bar customization (see /th rb for details)")
    end
end

-- Set up core events (target tracking events are registered dynamically)
TargetHelper:RegisterEvent("ADDON_LOADED")
TargetHelper:RegisterEvent("PLAYER_ENTERING_WORLD")
TargetHelper:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
TargetHelper:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Entering combat
TargetHelper:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leaving combat
TargetHelper:SetScript("OnEvent", OnEvent)
