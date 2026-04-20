-- Resource Bar Customization: Configurable thresholds, colors, and highlights
-- Version: 2.0.0
-- Compatible with: WoW 12.0.1+ (The War Within)
-- Rewritten using ClassResourceBar patterns for robust event handling

-------------------------------------------------------------------------------
-- Module Declaration
-------------------------------------------------------------------------------
local ResourceBar = CreateFrame("Frame", "SidekickResourceBarFrame")
ResourceBar:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

-------------------------------------------------------------------------------
-- Local State
-------------------------------------------------------------------------------
local powerBarFrame = nil
local markerFrames = {}
local highlightFrame = nil
local originalBarColor = {}
local isEnabled = false
local isInitialized = false
local moduleLoaded = false

-- Retry tracking for frame finding
local findFrameAttempts = 0
local MAX_FIND_ATTEMPTS = 10

-------------------------------------------------------------------------------
-- Configuration Constants
-------------------------------------------------------------------------------
local FEATURE_MARKERS = "markers"
local FEATURE_COLORS = "colors"
local FEATURE_HIGHLIGHTS = "highlights"

-------------------------------------------------------------------------------
-- Database Helpers
-------------------------------------------------------------------------------

-- Ensure database structure exists
local function EnsureDatabase()
    if not SidekickDB then
        SidekickDB = {}
    end

    if not SidekickDB.resourceBar then
        SidekickDB.resourceBar = {
            enabled = false,
            features = {
                [FEATURE_MARKERS] = true,
                [FEATURE_COLORS] = true,
                [FEATURE_HIGHLIGHTS] = true,
            },
            thresholds = {}
        }
    end

    -- Ensure features table exists
    if not SidekickDB.resourceBar.features then
        SidekickDB.resourceBar.features = {
            [FEATURE_MARKERS] = true,
            [FEATURE_COLORS] = true,
            [FEATURE_HIGHLIGHTS] = true,
        }
    end

    -- Ensure thresholds table exists
    if not SidekickDB.resourceBar.thresholds then
        SidekickDB.resourceBar.thresholds = {}
    end

    -- Sync local state
    isEnabled = SidekickDB.resourceBar.enabled or false
end

-- Safe feature check
local function IsFeatureEnabled(feature)
    if not SidekickDB or not SidekickDB.resourceBar or not SidekickDB.resourceBar.features then
        return false
    end
    return SidekickDB.resourceBar.features[feature] or false
end

-- Safe thresholds access
local function GetThresholds()
    if not SidekickDB or not SidekickDB.resourceBar or not SidekickDB.resourceBar.thresholds then
        return {}
    end
    return SidekickDB.resourceBar.thresholds
end

-------------------------------------------------------------------------------
-- Power Detection
-------------------------------------------------------------------------------

-- Get current power and max power (WoW 12.0+ compatible)
local function GetPowerInfo()
    local powerType, powerToken = UnitPowerType("player")
    if not powerType then
        return 0, 100, nil
    end

    local currentPower = UnitPower("player", powerType) or 0
    local maxPower = UnitPowerMax("player", powerType) or 100

    -- Handle alternate power types (like Balance Druid's Astral Power)
    if powerToken == "LUNAR_POWER" or powerToken == "ASTRAL_POWER" then
        -- Method 1: Try Enum (modern API)
        if Enum and Enum.PowerType and Enum.PowerType.AstralPower then
            currentPower = UnitPower("player", Enum.PowerType.AstralPower) or 0
            maxPower = UnitPowerMax("player", Enum.PowerType.AstralPower) or 100
        -- Method 2: Try numeric power type 8 (Astral Power)
        elseif UnitPowerMax("player", 8) > 0 then
            currentPower = UnitPower("player", 8) or 0
            maxPower = UnitPowerMax("player", 8) or 100
        end
    end

    -- Ensure valid values
    if maxPower == 0 then
        maxPower = 100
    end

    return currentPower, maxPower, powerType
end

-------------------------------------------------------------------------------
-- Frame Finding
-------------------------------------------------------------------------------

-- Find the power bar frame (WoW 12.0+ compatible with fallbacks)
local function FindPowerBarFrame()
    if not PlayerFrame then
        return nil
    end

    -- Method 1: Try alternate power bar first (for specs like Balance Druid with Astral Power)
    if PlayerFrame.AlternatePowerBar and PlayerFrame.AlternatePowerBar.IsShown then
        if PlayerFrame.AlternatePowerBar:IsShown() then
            return PlayerFrame.AlternatePowerBar
        end
    end

    -- Method 2: Try modern 11.0+ structure
    if PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain then
        local manaBar = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBar
        if manaBar and manaBar.IsShown and manaBar:IsShown() then
            return manaBar
        end
    end

    -- Method 3: Try direct PlayerFrame.manabar (12.0 might have simplified)
    if PlayerFrame.manabar and PlayerFrame.manabar.IsShown and PlayerFrame.manabar:IsShown() then
        return PlayerFrame.manabar
    end

    -- Method 4: Scan PlayerFrame children for StatusBar with power/mana
    local powerType = UnitPowerType("player")
    if powerType then
        local currentPower = UnitPower("player", powerType) or 0

        local children = {PlayerFrame:GetChildren()}
        for _, region in pairs(children) do
            if region and region.GetStatusBarTexture and region.GetValue then
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

-------------------------------------------------------------------------------
-- Marker Management
-------------------------------------------------------------------------------

-- Create threshold marker line
local function CreateMarker(parent, threshold)
    if not parent or not parent.CreateTexture then
        return nil
    end

    local height = parent:GetHeight()
    if not height or height == 0 then
        return nil
    end

    local marker = parent:CreateTexture(nil, "OVERLAY")
    if not marker then
        return nil
    end

    local color = threshold.color or {r = 1, g = 1, b = 1}
    marker:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, 0.9)
    marker:SetWidth(2)
    marker:SetHeight(height)

    return marker
end

-- Update marker positions based on thresholds
local function UpdateMarkers()
    -- Clear old markers first
    for _, marker in pairs(markerFrames) do
        if marker and marker.Hide then
            marker:Hide()
        end
    end
    markerFrames = {}

    if not IsFeatureEnabled(FEATURE_MARKERS) then
        return
    end

    local _, maxPower = GetPowerInfo()
    if not powerBarFrame or maxPower == 0 then
        return
    end

    local barWidth = powerBarFrame:GetWidth()
    if not barWidth or barWidth == 0 then
        return
    end

    -- Create new markers
    local thresholds = GetThresholds()
    for i, threshold in ipairs(thresholds) do
        if threshold and threshold.value then
            local percent = threshold.value / maxPower
            local marker = CreateMarker(powerBarFrame, threshold)

            if marker then
                local xOffset = barWidth * percent
                marker:ClearAllPoints()
                marker:SetPoint("LEFT", powerBarFrame, "LEFT", xOffset, 0)
                marker:Show()
                markerFrames[i] = marker
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Color Management
-------------------------------------------------------------------------------

-- Get the active threshold based on current power
local function GetActiveThreshold(currentPower)
    local activeThreshold = nil
    local thresholds = GetThresholds()

    -- Find the highest threshold that we've met
    for _, threshold in ipairs(thresholds) do
        if threshold and threshold.value and currentPower >= threshold.value then
            if not activeThreshold or threshold.value > activeThreshold.value then
                activeThreshold = threshold
            end
        end
    end

    return activeThreshold
end

-- Update bar color based on current power
local function UpdateBarColor(currentPower)
    if not powerBarFrame or not powerBarFrame.SetStatusBarColor then
        return
    end

    if not IsFeatureEnabled(FEATURE_COLORS) then
        -- Restore original color
        if originalBarColor.r then
            powerBarFrame:SetStatusBarColor(originalBarColor.r, originalBarColor.g, originalBarColor.b)
        end
        return
    end

    local activeThreshold = GetActiveThreshold(currentPower)

    if activeThreshold and activeThreshold.color then
        powerBarFrame:SetStatusBarColor(
            activeThreshold.color.r or 1,
            activeThreshold.color.g or 1,
            activeThreshold.color.b or 1
        )
    else
        -- Restore original color when below all thresholds
        if originalBarColor.r then
            powerBarFrame:SetStatusBarColor(originalBarColor.r, originalBarColor.g, originalBarColor.b)
        end
    end
end

-------------------------------------------------------------------------------
-- Highlight Management
-------------------------------------------------------------------------------

-- Create highlight frame if it doesn't exist
local function CreateHighlightFrame()
    if highlightFrame then
        return highlightFrame
    end

    if not powerBarFrame then
        return nil
    end

    highlightFrame = CreateFrame("Frame", "SidekickResourceHighlight", powerBarFrame)
    if not highlightFrame then
        return nil
    end

    highlightFrame:SetAllPoints(powerBarFrame)
    highlightFrame:SetFrameStrata("HIGH")

    -- Create glow texture
    local glow = highlightFrame:CreateTexture(nil, "OVERLAY")
    if glow then
        glow:SetAllPoints(highlightFrame)
        glow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0)
        highlightFrame.glow = glow
    end

    return highlightFrame
end

-- Update highlight based on current power
local function UpdateHighlight(currentPower)
    if not IsFeatureEnabled(FEATURE_HIGHLIGHTS) then
        if highlightFrame and highlightFrame.glow then
            highlightFrame.glow:SetAlpha(0)
        end
        return
    end

    if not highlightFrame then
        CreateHighlightFrame()
    end

    if not highlightFrame or not highlightFrame.glow then
        return
    end

    local activeThreshold = GetActiveThreshold(currentPower)

    if activeThreshold and activeThreshold.color then
        highlightFrame.glow:SetVertexColor(
            activeThreshold.color.r or 1,
            activeThreshold.color.g or 1,
            activeThreshold.color.b or 1
        )
        highlightFrame.glow:SetAlpha(0.5)
    else
        highlightFrame.glow:SetAlpha(0)
    end
end

-------------------------------------------------------------------------------
-- Main Update Functions
-------------------------------------------------------------------------------

-- Main update function called when power changes
local function OnPowerUpdate()
    if not isEnabled or not powerBarFrame then
        return
    end

    local currentPower, maxPower = GetPowerInfo()

    UpdateBarColor(currentPower)
    UpdateHighlight(currentPower)
end

-- Initialize the resource bar customization
local function Initialize()
    if isInitialized then
        return
    end

    powerBarFrame = FindPowerBarFrame()

    if not powerBarFrame then
        findFrameAttempts = findFrameAttempts + 1

        if findFrameAttempts < MAX_FIND_ATTEMPTS then
            -- Try again in 1 second
            C_Timer.After(1, Initialize)
        else
            -- Give up after max attempts
            print("|cFFFF0000Sidekick ResourceBar: Could not find power bar frame after " .. MAX_FIND_ATTEMPTS .. " attempts|r")
        end
        return
    end

    -- Store original bar color
    if powerBarFrame.GetStatusBarColor then
        local r, g, b, a = powerBarFrame:GetStatusBarColor()
        originalBarColor = {r = r, g = g, b = b, a = a}
    end

    isInitialized = true
    findFrameAttempts = 0

    UpdateMarkers()
    OnPowerUpdate()
end

-- Cleanup function
local function Cleanup()
    -- Restore original state
    if powerBarFrame and powerBarFrame.SetStatusBarColor and originalBarColor.r then
        powerBarFrame:SetStatusBarColor(originalBarColor.r, originalBarColor.g, originalBarColor.b)
    end

    -- Hide markers
    for _, marker in pairs(markerFrames) do
        if marker and marker.Hide then
            marker:Hide()
        end
    end
    markerFrames = {}

    -- Hide highlight
    if highlightFrame and highlightFrame.glow then
        highlightFrame.glow:SetAlpha(0)
    end

    isInitialized = false
    findFrameAttempts = 0
end

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

function ResourceBar:PLAYER_ENTERING_WORLD()
    if not moduleLoaded then
        return
    end

    EnsureDatabase()

    if isEnabled then
        C_Timer.After(0.5, Initialize)
    end
end

function ResourceBar:UNIT_POWER_UPDATE(unit)
    if unit ~= "player" or not isEnabled then
        return
    end
    OnPowerUpdate()
end

function ResourceBar:UNIT_MAXPOWER(unit)
    if unit ~= "player" or not isEnabled then
        return
    end
    UpdateMarkers()
    OnPowerUpdate()
end

function ResourceBar:PLAYER_SPECIALIZATION_CHANGED()
    if not isEnabled then
        return
    end

    -- Power bar might change with spec
    C_Timer.After(0.5, function()
        -- Reset initialization state
        isInitialized = false
        powerBarFrame = nil

        -- Re-find the power bar (it might have changed)
        powerBarFrame = FindPowerBarFrame()

        if powerBarFrame then
            -- Re-capture original color after spec change
            if powerBarFrame.GetStatusBarColor then
                local r, g, b, a = powerBarFrame:GetStatusBarColor()
                originalBarColor = {r = r, g = g, b = b, a = a}
            end

            isInitialized = true

            -- Re-initialize markers and colors
            UpdateMarkers()
            OnPowerUpdate()
        else
            -- Try full initialization again
            Initialize()
        end
    end)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Add threshold
function ResourceBar:AddThreshold(value, r, g, b, name)
    EnsureDatabase()

    table.insert(SidekickDB.resourceBar.thresholds, {
        value = value,
        color = {r = r, g = g, b = b},
        name = name or ("Threshold " .. value)
    })

    -- Sort thresholds by value
    table.sort(SidekickDB.resourceBar.thresholds, function(a, b)
        return (a.value or 0) < (b.value or 0)
    end)

    if isEnabled and isInitialized then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Remove threshold
function ResourceBar:RemoveThreshold(index)
    EnsureDatabase()

    if not SidekickDB.resourceBar.thresholds[index] then
        return
    end

    table.remove(SidekickDB.resourceBar.thresholds, index)

    if isEnabled and isInitialized then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Clear all thresholds
function ResourceBar:ClearThresholds()
    EnsureDatabase()

    SidekickDB.resourceBar.thresholds = {}

    if isEnabled and isInitialized then
        UpdateMarkers()
        OnPowerUpdate()
    end
end

-- Enable/disable resource bar customization
function ResourceBar:SetEnabled(enabled)
    EnsureDatabase()

    SidekickDB.resourceBar.enabled = enabled
    isEnabled = enabled

    if enabled then
        self:RegisterEvent("UNIT_POWER_UPDATE")
        self:RegisterEvent("UNIT_MAXPOWER")
        Initialize()
    else
        self:UnregisterEvent("UNIT_POWER_UPDATE")
        self:UnregisterEvent("UNIT_MAXPOWER")
        Cleanup()
    end
end

-- Toggle feature
function ResourceBar:ToggleFeature(feature)
    EnsureDatabase()

    local currentValue = SidekickDB.resourceBar.features[feature] or false
    SidekickDB.resourceBar.features[feature] = not currentValue

    if isEnabled and isInitialized then
        UpdateMarkers()
        OnPowerUpdate()
    end

    return SidekickDB.resourceBar.features[feature]
end

-- Get feature status
function ResourceBar:IsFeatureEnabled(feature)
    return IsFeatureEnabled(feature)
end

-- List thresholds
function ResourceBar:ListThresholds()
    return GetThresholds()
end

-------------------------------------------------------------------------------
-- Initialize Module
-------------------------------------------------------------------------------

-- Wait for addon to be fully loaded before initializing
C_Timer.After(0.1, function()
    EnsureDatabase()
    moduleLoaded = true

    -- Register core events
    ResourceBar:RegisterEvent("PLAYER_ENTERING_WORLD")
    ResourceBar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    -- If already enabled, register power events
    if isEnabled then
        ResourceBar:RegisterEvent("UNIT_POWER_UPDATE")
        ResourceBar:RegisterEvent("UNIT_MAXPOWER")
    end
end)

-- Export
_G.SidekickResourceBar = ResourceBar
