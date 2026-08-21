-- Resource Bar Customization: Configurable thresholds, colors, and highlights
-- Version: 3.0.0
-- Compatible with: WoW 12.0.x (Midnight) and later
--
-- Player secondary resources (Astral Power, Combo Points, Holy Power, Chi,
-- Runes, Soul Shards, Arcane Charges, Essence) are NOT secret under Midnight,
-- so the marker/color math below works normally for them. Primary power (mana,
-- energy, rage, fury) can be a Secret Value in restricted combat; reads of the
-- current value are therefore guarded with issecretvalue() and value-based
-- coloring is skipped rather than erroring when the value is secret.
-- See: https://warcraft.wiki.gg/wiki/Secret_Values

-------------------------------------------------------------------------------
-- Module Declaration
-------------------------------------------------------------------------------
local addonName, ns = ...
ns = ns or {}

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
local overlayFrame = nil
local markerFrames = {}
local highlightFrame = nil
local originalBarColor = {}
local isEnabled = false
local isInitialized = false
local moduleLoaded = false

-- Guards reentrancy when our own SetStatusBarColor call triggers the color hook.
local applyingColor = false

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
-- Secret Value Helper
-------------------------------------------------------------------------------

-- Shared across Sidekick's files via the addon namespace. issecretvalue may not
-- exist on pre-12.0 clients, so alias it to a no-op. Guarding with issecretvalue
-- is preferred over pcall, which carries roughly 10x the overhead of a native check.
if not ns.IsSecret then
    local issecretvalue = issecretvalue or function() return false end
    function ns.IsSecret(value)
        return issecretvalue(value)
    end
end
local IsSecret = ns.IsSecret

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
            anchor = "auto",
            features = {
                [FEATURE_MARKERS] = true,
                [FEATURE_COLORS] = true,
                [FEATURE_HIGHLIGHTS] = true,
            },
            thresholds = {}
        }
    end

    -- Ensure anchor exists for databases created before this option
    if not SidekickDB.resourceBar.anchor then
        SidekickDB.resourceBar.anchor = "auto"
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
        else
            -- Method 2: Try numeric power type 8 (Astral Power). Guard the max
            -- against a secret value before comparing it to zero.
            local astralMax = UnitPowerMax("player", 8)
            if not IsSecret(astralMax) and astralMax > 0 then
                currentPower = UnitPower("player", 8) or 0
                maxPower = astralMax
            end
        end
    end

    -- Ensure valid values. Max power is rarely secret, but guard before comparing.
    if not IsSecret(maxPower) and maxPower == 0 then
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

    -- Method 4: Scan PlayerFrame children for a StatusBar whose value matches the
    -- player's current power. Player power can be a Secret Value in restricted
    -- combat, and comparing a secret raises an immediate Lua error, so bail out of
    -- the value match when either side is secret and rely on the frame paths above.
    local powerType = UnitPowerType("player")
    if powerType then
        local currentPower = UnitPower("player", powerType)
        if currentPower ~= nil and not IsSecret(currentPower) then
            local children = {PlayerFrame:GetChildren()}
            for _, region in pairs(children) do
                if region and region.GetStatusBarTexture and region.GetValue then
                    local barValue = region:GetValue()

                    -- If bar value matches current power, we found it
                    if barValue ~= nil and not IsSecret(barValue)
                        and math.abs(barValue - currentPower) < 0.1 then
                        return region
                    end
                end
            end
        end
    end

    return nil
end

-- Resolve which bar to attach to: an explicit user-chosen frame by global name,
-- otherwise the auto-detected Blizzard power bar. This is what lets the overlay
-- be pointed at a different bar (for example one provided by another addon).
local function ResolveTargetBar()
    local anchor = SidekickDB and SidekickDB.resourceBar and SidekickDB.resourceBar.anchor
    if anchor and anchor ~= "auto" then
        local frame = _G[anchor]
        if frame then
            return frame
        end
    end
    return FindPowerBarFrame()
end

-- Our markers and highlight live on this overlay, anchored over the target bar,
-- so we never add child regions to Blizzard's protected frame (a taint vector).
local function EnsureOverlay()
    if overlayFrame then
        return overlayFrame
    end
    overlayFrame = CreateFrame("Frame", "SidekickResourceOverlay", UIParent)
    overlayFrame:SetFrameStrata("HIGH")
    return overlayFrame
end

-- Apply a bar color through a reentrancy guard so our own call does not recurse
-- through the SetStatusBarColor hook installed in Initialize.
local function SetBarColor(r, g, b)
    if not powerBarFrame or not powerBarFrame.SetStatusBarColor then
        return
    end
    applyingColor = true
    powerBarFrame:SetStatusBarColor(r, g, b)
    applyingColor = false
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
    if not powerBarFrame or not overlayFrame or IsSecret(maxPower) or maxPower == 0 then
        return
    end

    local barWidth = powerBarFrame:GetWidth()
    if not barWidth or barWidth == 0 then
        return
    end

    -- Create new markers on our overlay, positioned across the target bar's width
    local thresholds = GetThresholds()
    for i, threshold in ipairs(thresholds) do
        if threshold and threshold.value then
            local percent = threshold.value / maxPower
            local marker = CreateMarker(overlayFrame, threshold)

            if marker then
                local xOffset = barWidth * percent
                marker:ClearAllPoints()
                marker:SetPoint("LEFT", overlayFrame, "LEFT", xOffset, 0)
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

-- Restore the power bar to its captured default color
local function RestoreBarColor()
    if originalBarColor.r then
        SetBarColor(originalBarColor.r, originalBarColor.g, originalBarColor.b)
    end
end

-- Update bar color based on current power
local function UpdateBarColor(currentPower)
    if not powerBarFrame or not powerBarFrame.SetStatusBarColor then
        return
    end

    if not IsFeatureEnabled(FEATURE_COLORS) then
        RestoreBarColor()
        return
    end

    local activeThreshold = GetActiveThreshold(currentPower)

    if activeThreshold and activeThreshold.color then
        SetBarColor(
            activeThreshold.color.r or 1,
            activeThreshold.color.g or 1,
            activeThreshold.color.b or 1
        )
    else
        -- Restore original color when below all thresholds
        RestoreBarColor()
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

    if not overlayFrame then
        return nil
    end

    highlightFrame = CreateFrame("Frame", "SidekickResourceHighlight", overlayFrame)
    if not highlightFrame then
        return nil
    end

    highlightFrame:SetAllPoints(overlayFrame)
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

    local currentPower = GetPowerInfo()

    -- Primary power can be a Secret Value in restricted combat. We cannot compare
    -- it against thresholds, so restore the default look and skip value-based
    -- coloring rather than trigger a Lua error. Secondary resources (the common
    -- use case) are never secret and fall through to the normal path.
    if IsSecret(currentPower) then
        RestoreBarColor()
        if highlightFrame and highlightFrame.glow then
            highlightFrame.glow:SetAlpha(0)
        end
        return
    end

    UpdateBarColor(currentPower)
    UpdateHighlight(currentPower)
end

-- Install a post-hook so our threshold color survives Blizzard's own updates to
-- the bar, and so we never taint the frame by owning its color outright. The
-- hook is a secure post-hook; the reentrancy guard stops our own reapply from
-- looping back through it.
local function HookBarColor()
    if not powerBarFrame or powerBarFrame.__sidekickColorHooked then
        return
    end
    if not hooksecurefunc or not powerBarFrame.SetStatusBarColor then
        return
    end

    hooksecurefunc(powerBarFrame, "SetStatusBarColor", function()
        if applyingColor or not isEnabled then
            return
        end
        if not IsFeatureEnabled(FEATURE_COLORS) then
            return
        end

        local currentPower = GetPowerInfo()
        if IsSecret(currentPower) then
            return
        end

        local active = GetActiveThreshold(currentPower)
        if active and active.color then
            SetBarColor(active.color.r or 1, active.color.g or 1, active.color.b or 1)
        end
    end)

    powerBarFrame.__sidekickColorHooked = true
end

-- Initialize the resource bar customization
local function Initialize()
    if isInitialized then
        return
    end

    powerBarFrame = ResolveTargetBar()

    if not powerBarFrame then
        findFrameAttempts = findFrameAttempts + 1

        if findFrameAttempts < MAX_FIND_ATTEMPTS then
            -- Try again shortly; the target bar may not be laid out yet
            C_Timer.After(1, Initialize)
        else
            -- Give up after max attempts
            print("|cFFFF0000Sidekick ResourceBar: Could not find a bar to attach to after " .. MAX_FIND_ATTEMPTS .. " attempts|r")
        end
        return
    end

    -- Anchor our overlay over the target bar so markers/highlight never become
    -- children of a protected frame
    EnsureOverlay()
    overlayFrame:SetAllPoints(powerBarFrame)
    overlayFrame:Show()

    -- Store original bar color for restore
    if powerBarFrame.GetStatusBarColor then
        local r, g, b, a = powerBarFrame:GetStatusBarColor()
        originalBarColor = {r = r, g = g, b = b, a = a}
    end

    HookBarColor()

    isInitialized = true
    findFrameAttempts = 0

    UpdateMarkers()
    OnPowerUpdate()
end

-- Cleanup function
local function Cleanup()
    -- Restore original bar color
    RestoreBarColor()

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

    -- Hide the overlay so nothing lingers over the bar
    if overlayFrame then
        overlayFrame:Hide()
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

    -- Power bar might change with spec; let Initialize re-resolve and re-anchor
    C_Timer.After(0.5, function()
        isInitialized = false
        powerBarFrame = nil
        Initialize()
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
        self:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        self:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        Initialize()
    else
        self:UnregisterEvent("UNIT_POWER_UPDATE")
        self:UnregisterEvent("UNIT_MAXPOWER")
        Cleanup()
    end
end

-- Choose which bar the overlay attaches to. Pass a frame's global name to attach
-- to that bar, or "auto"/nil to use the detected Blizzard power bar.
function ResourceBar:SetAnchor(frameName)
    EnsureDatabase()

    SidekickDB.resourceBar.anchor = frameName or "auto"

    -- Re-resolve against the new anchor
    if isEnabled then
        Cleanup()
        Initialize()
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

-- Set up saved variables and core events once the addon's data is available,
-- rather than guessing with an arbitrary timer.
function ResourceBar:ADDON_LOADED(addonName)
    if addonName ~= "Sidekick" then
        return
    end

    EnsureDatabase()
    moduleLoaded = true

    -- Register core events
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    -- If already enabled, register player-scoped power events
    if isEnabled then
        self:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        self:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    end

    self:UnregisterEvent("ADDON_LOADED")
end

ResourceBar:RegisterEvent("ADDON_LOADED")

-- Export
_G.SidekickResourceBar = ResourceBar
