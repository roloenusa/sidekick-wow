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

-- Slash command handler
SLASH_TARGETHELPER1 = "/targethelper"
SLASH_TARGETHELPER2 = "/th"
SlashCmdList["TARGETHELPER"] = function(msg)
    msg = string.lower(msg or "")

    if msg == "toggle" then
        TargetHelperDB.enabled = not TargetHelperDB.enabled
        if TargetHelperDB.enabled then
            print("|cFF00FF00Target Helper: Enabled|r")
        else
            print("|cFFFF0000Target Helper: Disabled|r")
            HideLowHealthGlow()
        end
        UpdateEventRegistration()
    else
        print("|cFF00FF00Target Helper Commands:|r")
        print("/targethelper toggle - Enable/disable the addon")
    end
end

-- Set up core events (target tracking events are registered dynamically)
TargetHelper:RegisterEvent("ADDON_LOADED")
TargetHelper:RegisterEvent("PLAYER_ENTERING_WORLD")
TargetHelper:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
TargetHelper:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Entering combat
TargetHelper:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leaving combat
TargetHelper:SetScript("OnEvent", OnEvent)
