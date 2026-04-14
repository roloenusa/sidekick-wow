-- Resource Bar Customization: Configurable thresholds, colors, and highlights

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
    if not TargetHelperDB.resourceBar then
        TargetHelperDB.resourceBar = {
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

-- Get current power and max power
local function GetPowerInfo()
    local powerType = UnitPowerType("player")
    local currentPower = UnitPower("player", powerType)
    local maxPower = UnitPowerMax("player", powerType)
    return currentPower, maxPower, powerType
end

-- Find the power bar frame
local function FindPowerBarFrame()
    -- Try alternate power bar first (for specs like Balance Druid with Astral Power)
    if PlayerFrame_AlternateManaBar and PlayerFrame_AlternateManaBar:IsShown() then
        return PlayerFrame_AlternateManaBar
    end

    -- Try class resource bar
    if ClassResourceBarFrame and ClassResourceBarFrame:IsShown() then
        return ClassResourceBarFrame
    end

    -- Fall back to standard mana bar
    if PlayerFrame.manabar then
        return PlayerFrame.manabar
    end

    return nil
end

-- Create threshold marker lines
local function CreateMarker(parent, threshold)
    local marker = parent:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(threshold.color.r, threshold.color.g, threshold.color.b, 0.9)
    marker:SetWidth(2)
    marker:SetHeight(parent:GetHeight())
    return marker
end

-- Update marker positions based on thresholds
local function UpdateMarkers()
    if not TargetHelperDB.resourceBar.features[FEATURE_MARKERS] then
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
    for i, threshold in ipairs(TargetHelperDB.resourceBar.thresholds) do
        local percent = threshold.value / maxPower
        local marker = CreateMarker(powerBarFrame, threshold)
        local xOffset = barWidth * percent

        marker:SetPoint("LEFT", powerBarFrame, "LEFT", xOffset, 0)
        marker:Show()

        markerFrames[i] = marker
    end
end

-- Get the active threshold based on current power
local function GetActiveThreshold(currentPower)
    local activeThreshold = nil

    -- Find the highest threshold that we've met
    for _, threshold in ipairs(TargetHelperDB.resourceBar.thresholds) do
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

    if not TargetHelperDB.resourceBar.features[FEATURE_COLORS] then
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

    highlightFrame = CreateFrame("Frame", "TargetHelperResourceHighlight", powerBarFrame)
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
    if not TargetHelperDB.resourceBar.features[FEATURE_HIGHLIGHTS] then
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
    if not TargetHelperDB.resourceBar.enabled then return end

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
        if TargetHelperDB.resourceBar.enabled then
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
            powerBarFrame = FindPowerBarFrame()
            if powerBarFrame then
                local r, g, b, a = powerBarFrame:GetStatusBarColor()
                originalBarColor = {r = r, g = g, b = b, a = a}
            end
            Initialize()
        end)
    end
end

-- Add threshold
function ResourceBar:AddThreshold(value, r, g, b, name)
    table.insert(TargetHelperDB.resourceBar.thresholds, {
        value = value,
        color = {r = r, g = g, b = b},
        name = name or ("Threshold " .. value)
    })

    -- Sort thresholds by value
    table.sort(TargetHelperDB.resourceBar.thresholds, function(a, b)
        return a.value < b.value
    end)

    if TargetHelperDB.resourceBar.enabled then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Remove threshold
function ResourceBar:RemoveThreshold(index)
    table.remove(TargetHelperDB.resourceBar.thresholds, index)

    if TargetHelperDB.resourceBar.enabled then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Clear all thresholds
function ResourceBar:ClearThresholds()
    TargetHelperDB.resourceBar.thresholds = {}

    if TargetHelperDB.resourceBar.enabled then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Enable/disable resource bar customization
function ResourceBar:SetEnabled(enabled)
    TargetHelperDB.resourceBar.enabled = enabled

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
    TargetHelperDB.resourceBar.features[feature] = not TargetHelperDB.resourceBar.features[feature]

    if TargetHelperDB.resourceBar.enabled then
        UpdateMarkers()
        OnPowerUpdate()
    end

    return TargetHelperDB.resourceBar.features[feature]
end

-- Get feature status
function ResourceBar:IsFeatureEnabled(feature)
    return TargetHelperDB.resourceBar.features[feature]
end

-- List thresholds
function ResourceBar:ListThresholds()
    return TargetHelperDB.resourceBar.thresholds
end

-- Initialize config when addon loads
InitializeConfig()

-- Register events
ResourceBar:RegisterEvent("PLAYER_ENTERING_WORLD")
ResourceBar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ResourceBar:SetScript("OnEvent", OnEvent)

-- Export
_G.TargetHelperResourceBar = ResourceBar
