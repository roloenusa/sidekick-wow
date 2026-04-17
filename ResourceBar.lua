-- Resource Bar Customization: Configurable thresholds, colors, and highlights
-- Version: 1.1.0
-- Compatible with: WoW 12.0.1+ (The War Within)
-- Features: Threshold markers, dynamic colors, power bar highlights

local ResourceBar = CreateFrame("Frame")
local powerBarFrame = nil
local markerFrames = {}
local highlightFrame = nil
local originalBarColor = {}

-- Feature toggles
local FEATURE_MARKERS = "markers"
local FEATURE_COLORS = "colors"
local FEATURE_HIGHLIGHTS = "highlights"

-- Initialize default configuration
local function InitializeConfig()
    if not SidekickDB.resourceBar then
        SidekickDB.resourceBar = {
            enabled = false,
            features = {
                [FEATURE_MARKERS] = true,
                [FEATURE_COLORS] = true,
                [FEATURE_HIGHLIGHTS] = true,
            },
            thresholds = {
                -- Example default for Balance Druid
                -- {value = 40, color = {r = 1.0, g = 1.0, b = 0.0}, name = "Starsurge"},
                -- {value = 50, color = {r = 0.0, g = 0.5, b = 1.0}, name = "Starfall"},
            }
        }
    end
end

-- Get current power and max power (WoW 12.0+ compatible)
local function GetPowerInfo()
    local powerType, powerToken = UnitPowerType("player")
    local currentPower = UnitPower("player", powerType)
    local maxPower = UnitPowerMax("player", powerType)

    -- Handle alternate power types (like Balance Druid's Astral Power)
    -- Try multiple methods for 12.0 compatibility
    if powerToken == "LUNAR_POWER" or powerToken == "ASTRAL_POWER" then
        -- Method 1: Try Enum (modern API)
        if Enum and Enum.PowerType and Enum.PowerType.AstralPower then
            currentPower = UnitPower("player", Enum.PowerType.AstralPower)
            maxPower = UnitPowerMax("player", Enum.PowerType.AstralPower)
        -- Method 2: Try numeric power type 8 (Astral Power)
        elseif UnitPower("player", 8) > 0 or UnitPowerMax("player", 8) > 0 then
            currentPower = UnitPower("player", 8)
            maxPower = UnitPowerMax("player", 8)
        end
    end

    -- Ensure we have valid values
    currentPower = currentPower or 0
    maxPower = maxPower or 100

    return currentPower, maxPower, powerType
end

-- Find the power bar frame (WoW 12.0+ compatible with fallbacks)
local function FindPowerBarFrame()
    -- Method 1: Try alternate power bar first (for specs like Balance Druid with Astral Power)
    -- This works in 11.0 and should work in 12.0+
    if PlayerFrame and PlayerFrame.AlternatePowerBar and PlayerFrame.AlternatePowerBar:IsShown() then
        return PlayerFrame.AlternatePowerBar
    end

    -- Method 2: Try modern 11.0+ structure
    if PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain then
        local manaBar = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBar
        if manaBar and manaBar:IsShown() then
            return manaBar
        end
    end

    -- Method 3: Try direct PlayerFrame.manabar (12.0 might have simplified)
    if PlayerFrame and PlayerFrame.manabar and PlayerFrame.manabar:IsShown() then
        return PlayerFrame.manabar
    end

    -- Method 4: Scan PlayerFrame children for StatusBar with power/mana
    if PlayerFrame then
        for _, region in pairs({PlayerFrame:GetChildren()}) do
            if region and region.GetStatusBarTexture then
                local powerType = UnitPowerType("player")
                local currentPower = UnitPower("player", powerType)
                local barValue = region:GetValue() or 0

                -- If bar value matches current power, we found it
                if math.abs(barValue - currentPower) < 0.1 then
                    return region
                end
            end
        end
    end

    return nil
end

-- Create threshold marker lines
local function CreateMarker(parent, threshold)
    if not parent or not parent.CreateTexture then
        return nil
    end

    local height = parent:GetHeight()
    if not height or height == 0 then
        return nil
    end

    local marker = parent:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(threshold.color.r, threshold.color.g, threshold.color.b, 0.9)
    marker:SetWidth(2)
    marker:SetHeight(height)
    return marker
end

-- Update marker positions based on thresholds
local function UpdateMarkers()
    if not SidekickDB.resourceBar.features[FEATURE_MARKERS] then
        -- Hide all markers
        for _, marker in pairs(markerFrames) do
            marker:Hide()
        end
        return
    end

    local _, maxPower = GetPowerInfo()
    if not powerBarFrame or maxPower == 0 then return end

    local barWidth = powerBarFrame:GetWidth()

    -- Clear old markers
    for _, marker in pairs(markerFrames) do
        marker:Hide()
    end
    markerFrames = {}

    -- Create new markers
    for i, threshold in ipairs(SidekickDB.resourceBar.thresholds) do
        local percent = threshold.value / maxPower
        local marker = CreateMarker(powerBarFrame, threshold)

        if marker then
            local xOffset = barWidth * percent
            marker:SetPoint("LEFT", powerBarFrame, "LEFT", xOffset, 0)
            marker:Show()
            markerFrames[i] = marker
        end
    end
end

-- Get the active threshold based on current power
local function GetActiveThreshold(currentPower)
    local activeThreshold = nil

    -- Find the highest threshold that we've met
    for _, threshold in ipairs(SidekickDB.resourceBar.thresholds) do
        if currentPower >= threshold.value then
            if not activeThreshold or threshold.value > activeThreshold.value then
                activeThreshold = threshold
            end
        end
    end

    return activeThreshold
end

-- Update bar color based on current power
local function UpdateBarColor(currentPower)
    if not powerBarFrame then return end

    if not SidekickDB.resourceBar.features[FEATURE_COLORS] then
        -- Restore original color
        if originalBarColor.r then
            powerBarFrame:SetStatusBarColor(originalBarColor.r, originalBarColor.g, originalBarColor.b)
        end
        return
    end

    local activeThreshold = GetActiveThreshold(currentPower)

    if activeThreshold then
        powerBarFrame:SetStatusBarColor(
            activeThreshold.color.r,
            activeThreshold.color.g,
            activeThreshold.color.b
        )
    else
        -- Restore original color when below all thresholds
        if originalBarColor.r then
            powerBarFrame:SetStatusBarColor(originalBarColor.r, originalBarColor.g, originalBarColor.b)
        end
    end
end

-- Create highlight frame if it doesn't exist
local function CreateHighlightFrame()
    if highlightFrame then return highlightFrame end

    if not powerBarFrame then return nil end

    highlightFrame = CreateFrame("Frame", "SidekickResourceHighlight", powerBarFrame)
    highlightFrame:SetAllPoints(powerBarFrame)
    highlightFrame:SetFrameStrata("HIGH")

    -- Create glow texture
    local glow = highlightFrame:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints(highlightFrame)
    glow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)
    highlightFrame.glow = glow

    return highlightFrame
end

-- Update highlight based on current power
local function UpdateHighlight(currentPower)
    if not SidekickDB.resourceBar.features[FEATURE_HIGHLIGHTS] then
        if highlightFrame and highlightFrame.glow then
            highlightFrame.glow:SetAlpha(0)
        end
        return
    end

    if not highlightFrame then
        CreateHighlightFrame()
    end

    if not highlightFrame then return end

    local activeThreshold = GetActiveThreshold(currentPower)

    if activeThreshold then
        highlightFrame.glow:SetVertexColor(
            activeThreshold.color.r,
            activeThreshold.color.g,
            activeThreshold.color.b
        )
        highlightFrame.glow:SetAlpha(0.5)
    else
        highlightFrame.glow:SetAlpha(0)
    end
end

-- Main update function called when power changes
local function OnPowerUpdate()
    if not SidekickDB.resourceBar.enabled then return end

    local currentPower, maxPower = GetPowerInfo()

    UpdateBarColor(currentPower)
    UpdateHighlight(currentPower)
end

-- Initialize the resource bar customization
local function Initialize()
    powerBarFrame = FindPowerBarFrame()

    if not powerBarFrame then
        -- Try again in 1 second
        C_Timer.After(1, Initialize)
        return
    end

    -- Store original bar color
    local r, g, b, a = powerBarFrame:GetStatusBarColor()
    originalBarColor = {r = r, g = g, b = b, a = a}

    UpdateMarkers()
    OnPowerUpdate()
end

-- Event handler
local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if SidekickDB.resourceBar.enabled then
            C_Timer.After(0.5, Initialize)
        end
    elseif event == "UNIT_POWER_UPDATE" then
        local unit = ...
        if unit == "player" then
            OnPowerUpdate()
        end
    elseif event == "UNIT_MAXPOWER" then
        local unit = ...
        if unit == "player" then
            UpdateMarkers()
            OnPowerUpdate()
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Power bar might change with spec
        C_Timer.After(0.5, function()
            -- Re-find the power bar (it might have changed)
            powerBarFrame = FindPowerBarFrame()
            if powerBarFrame then
                -- Re-capture original color after spec change
                local r, g, b, a = powerBarFrame:GetStatusBarColor()
                originalBarColor = {r = r, g = g, b = b, a = a}

                -- Re-initialize markers and colors
                UpdateMarkers()
                OnPowerUpdate()
            end
        end)
    end
end

-- Add threshold
function ResourceBar:AddThreshold(value, r, g, b, name)
    table.insert(SidekickDB.resourceBar.thresholds, {
        value = value,
        color = {r = r, g = g, b = b},
        name = name or ("Threshold " .. value)
    })

    -- Sort thresholds by value
    table.sort(SidekickDB.resourceBar.thresholds, function(a, b)
        return a.value < b.value
    end)

    if SidekickDB.resourceBar.enabled then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Remove threshold
function ResourceBar:RemoveThreshold(index)
    table.remove(SidekickDB.resourceBar.thresholds, index)

    if SidekickDB.resourceBar.enabled then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Clear all thresholds
function ResourceBar:ClearThresholds()
    SidekickDB.resourceBar.thresholds = {}

    if SidekickDB.resourceBar.enabled then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Enable/disable resource bar customization
function ResourceBar:SetEnabled(enabled)
    SidekickDB.resourceBar.enabled = enabled

    if enabled then
        ResourceBar:RegisterEvent("UNIT_POWER_UPDATE")
        ResourceBar:RegisterEvent("UNIT_MAXPOWER")
        Initialize()
    else
        ResourceBar:UnregisterEvent("UNIT_POWER_UPDATE")
        ResourceBar:UnregisterEvent("UNIT_MAXPOWER")

        -- Restore original state
        if powerBarFrame and originalBarColor.r then
            powerBarFrame:SetStatusBarColor(originalBarColor.r, originalBarColor.g, originalBarColor.b)
        end

        for _, marker in pairs(markerFrames) do
            marker:Hide()
        end

        if highlightFrame and highlightFrame.glow then
            highlightFrame.glow:SetAlpha(0)
        end
    end
end

-- Toggle feature
function ResourceBar:ToggleFeature(feature)
    SidekickDB.resourceBar.features[feature] = not SidekickDB.resourceBar.features[feature]

    if SidekickDB.resourceBar.enabled then
        UpdateMarkers()
        OnPowerUpdate()
    end

    return SidekickDB.resourceBar.features[feature]
end

-- Get feature status
function ResourceBar:IsFeatureEnabled(feature)
    return SidekickDB.resourceBar.features[feature]
end

-- List thresholds
function ResourceBar:ListThresholds()
    return SidekickDB.resourceBar.thresholds
end

-- Initialize config when addon loads
InitializeConfig()

-- Register events
ResourceBar:RegisterEvent("PLAYER_ENTERING_WORLD")
ResourceBar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ResourceBar:SetScript("OnEvent", OnEvent)

-- Export
_G.SidekickResourceBar = ResourceBar
