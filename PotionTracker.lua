-- Create main addon frame
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Entering combat
f:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leaving combat
f:RegisterEvent("PLAYER_TARGET_CHANGED")  -- Target changed
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")  -- Add combat log event

local LOG_LEVELS = {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4,
}

local activeLogLevel = "INFO"

local function NormalizeLogLevel(level)
    if type(level) ~= "string" then
        return nil
    end

    local normalized = string.upper(level)
    if LOG_LEVELS[normalized] then
        return normalized
    end

    return nil
end

local function ShouldLog(level)
    local normalized = NormalizeLogLevel(level) or "INFO"
    local currentLevelValue = LOG_LEVELS[activeLogLevel] or LOG_LEVELS.INFO
    return LOG_LEVELS[normalized] <= currentLevelValue
end

local function SetActiveLogLevel(level)
    local normalized = NormalizeLogLevel(level)
    if not normalized then
        return false
    end

    activeLogLevel = normalized
    if PotionTrackerDB then
        PotionTrackerDB.logLevel = normalized
    end
    return true
end

-- Function to print messages with log levels
Print = function(msg, level)
    local normalized = NormalizeLogLevel(level) or "INFO"
    if ShouldLog(normalized) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FF00PotionTracker|r [%s]: %s", normalized, msg))
    end
end

local function Debug(msg)
    if ShouldLog("DEBUG") then
        Print(msg, "DEBUG")
    end
end

local function WithBackdrop(template)
    if not template or template == "" then
        return template
    end

    if BackdropTemplateMixin then
        return string.format("%s,BackdropTemplate", template)
    end

    return template
end

local UI = {
    Minimap = {},
    Options = {},
    BuffConfig = {},
}

-- Helper function to get table size
GetTableSize = function(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Function to export history as CSV (moved outside local scope)
local function FormatTargetDetails(targets)
    if type(targets) ~= "table" then
        return ""
    end

    local summaries = {}
    for _, info in ipairs(targets) do
        local name = info.name or "Unknown"
        local details = {}

        if info.level then
            table.insert(details, string.format("Lvl %d", info.level))
        end

        if info.classification and info.classification ~= "" then
            table.insert(details, info.classification)
        end

        if info.isElite then
            table.insert(details, "Elite")
        end

        if #details > 0 then
            name = string.format("%s (%s)", name, table.concat(details, " "))
        end

        table.insert(summaries, name)
    end

    return table.concat(summaries, "; ")
end

ExportCSV = function()
    if not PotionTrackerDB or not PotionTrackerDB.buffHistory or #PotionTrackerDB.buffHistory == 0 then
        Print("No events to export")
        return
    end

    -- Create CSV header
    local csv = "Timestamp,Event,Unit,Buff,Target,Duration,EncounterID,TargetLevel,TargetClassification,TargetCount,TargetDetails\n"

    -- Add each event
    for _, event in ipairs(PotionTrackerDB.buffHistory) do
        local timestamp = event.date or date("%Y-%m-%d %H:%M:%S", event.timestamp)
        -- Escape any commas in the fields
        local function escape(value)
            if value == nil then
                value = ""
            end

            if type(value) ~= "string" then
                value = tostring(value)
            end

            if value:find('"') then
                value = value:gsub('"', '""')
            end

            if value:find(",") or value:find("\n") or value:find('"') then
                return '"' .. value .. '"'
            end

            return value
        end

        -- Combine fields into CSV line
        local line = string.format("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
            escape(timestamp),
            escape(event.event or ""),
            escape(event.unit or ""),
            escape(event.buff or ""),
            escape(event.targetName or ""),
            escape(event.duration and tostring(event.duration) or ""),
            escape(event.encounterId or ""),
            escape(event.targetLevel or ""),
            escape(event.targetClassification or ""),
            escape(event.targetCount or ""),
            escape(FormatTargetDetails(event.targets))
        )

        csv = csv .. line
    end

    -- Save CSV data to SavedVariables (WoW addons cannot write files outside the game directory)
    if not PotionTrackerDB then
        PotionTrackerDB = {}
    end
    PotionTrackerDB.exportedCSV = csv
    
    Print("CSV data exported to SavedVariables!")
    Print("To access your CSV data:")
    Print("1. Use /pt showcsv to display the data in chat")
    Print("2. Copy the data and save it as a .csv file")
    Print("3. Or find it in your SavedVariables file after logout")
    Print("   Location: WTF\\Account\\[AccountName]\\SavedVariables\\PotionTracker.lua")
end

-- Initialize variables
local isTracking = false
local minimapIcon = nil
local buffHistory = {}
local previousBuffs = {}
local dropDown = nil  -- Move dropDown to global scope
local optionsPanel = nil

UI.Minimap.shapeFallbacks = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
}

local function PlayUISound(soundKitKey, fallback)
    if not PlaySound then
        return
    end

    if SOUNDKIT and SOUNDKIT[soundKitKey] then
        PlaySound(SOUNDKIT[soundKitKey])
    elseif type(fallback) == "string" then
        PlaySound(fallback)
    elseif type(soundKitKey) == "string" then
        PlaySound(soundKitKey)
    end
end

-- Forward declarations
local InitializeAllUnits
local UpdateOptionsPanel

local DEFAULT_HISTORY_LIMIT = 1000
local MIN_HISTORY_LIMIT = 100
local MAX_HISTORY_LIMIT = 5000

local function NormalizeHistoryLimit(value)
    local limit = tonumber(value) or DEFAULT_HISTORY_LIMIT
    limit = math.floor(limit)
    if limit < MIN_HISTORY_LIMIT then
        limit = MIN_HISTORY_LIMIT
    elseif limit > MAX_HISTORY_LIMIT then
        limit = MAX_HISTORY_LIMIT
    end
    return limit
end

local function GetLogLevelDisplay(level)
    if type(level) ~= "string" or level == "" then
        return ""
    end

    return level:sub(1, 1) .. string.lower(level:sub(2))
end

local function GetHistoryLimit()
    local limit = DEFAULT_HISTORY_LIMIT
    if PotionTrackerDB and PotionTrackerDB.historyLimit then
        limit = NormalizeHistoryLimit(PotionTrackerDB.historyLimit)
    end
    if not PotionTrackerDB then
        PotionTrackerDB = {}
    end
    PotionTrackerDB.historyLimit = limit
    return limit
end

local function EnforceHistoryLimit()
    if not buffHistory then return end

    local limit = GetHistoryLimit()
    while #buffHistory > limit do
        table.remove(buffHistory, 1)
    end

    if PotionTrackerDB then
        PotionTrackerDB.buffHistory = buffHistory
    end
end

local function SetHistoryLimit(value)
    if not PotionTrackerDB then
        PotionTrackerDB = {}
    end

    PotionTrackerDB.historyLimit = NormalizeHistoryLimit(value)
    EnforceHistoryLimit()
    return PotionTrackerDB.historyLimit
end

-- Function to toggle tracking
local function ToggleTracking()
    isTracking = not isTracking

    if not PotionTrackerDB then
        PotionTrackerDB = {}
    end
    PotionTrackerDB.isTracking = isTracking

    if isTracking then
        Print("Tracking started")

        -- Reset cached buff state and scan current units so we don't miss existing buffs
        previousBuffs = {}
        lastUnitUpdate = {}
        ResetCombatState()
        InitializeAllUnits()
    else
        Print("Tracking stopped")
        ResetCombatState()
    end

    UI.Minimap:UpdateIconState()
    UpdateOptionsPanel()
end

-- Create dropdown menu
function UI.Minimap:InitializeMenu(frame, level, menuList)
    local info = UIDropDownMenu_CreateInfo()

    info.text = "PotionTracker Options"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()  -- Reset info table for next button
    info.notCheckable = true
    info.text = "Configure Buffs"
    info.func = function()
        Debug("Configure Buffs clicked")
        UI.BuffConfig:Show()
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()  -- Reset info table for next button
    info.notCheckable = true
    info.text = "Export Data"
    info.func = function()
        ExportCSV()
        Debug("Export menu option selected")
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()  -- Reset info table for next button
    info.notCheckable = true
    info.text = "Clear History"
    info.func = function()
        -- Clear both in-memory and saved data
        buffHistory = {}
        PotionTrackerDB.buffHistory = {}
        PotionTrackerDB.exportedCSV = nil
        Print("History cleared. Fresh data will be saved going forward.")
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()  -- Reset info table for next button
    info.notCheckable = true
    info.text = "Show Stats"
    info.func = function()
        local count = #buffHistory
        Print(string.format("Tracking %d events", count))
    end
    UIDropDownMenu_AddButton(info, level)
end

-- Function to create minimap icon
function UI.Minimap:Create()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Button", "PotionTrackerMinimapIcon", Minimap)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    frame:SetMovable(false)
    
    -- Set size and position
    frame:SetWidth(32)
    frame:SetHeight(32)
    frame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Create the icon texture (should be behind the border)
    local icon = frame:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(16)
    icon:SetHeight(16)
    icon:SetTexture("Interface\\Icons\\INV_Potion_94")
    icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- This removes the icon border
    frame.texture = icon
    
    -- Create the border (it should be in front of the icon)
    local overlay = frame:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(54)
    overlay:SetHeight(54)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("CENTER", frame, "CENTER", 11, -11)
    
    -- Create the dropdown menu
    if not dropDown then
        dropDown = CreateFrame("Frame", "PotionTrackerDropDownMenu", UIParent, WithBackdrop("UIDropDownMenuTemplate"))
    end
    UIDropDownMenu_Initialize(dropDown, function(...)
        UI.Minimap:InitializeMenu(...)
    end)
    
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:RegisterForDrag("LeftButton")
    
    -- Minimap icon positioning
    local function UpdatePosition()
        local angle = math.rad(PotionTrackerDB.minimapPos or 45)
        local cosAngle = math.cos(angle)
        local sinAngle = math.sin(angle)
        local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
        local quadTable = (MinimapShapes and MinimapShapes[minimapShape])
            or UI.Minimap.shapeFallbacks[minimapShape]
            or UI.Minimap.shapeFallbacks.ROUND

        local quadrant = 1
        if cosAngle < 0 then
            quadrant = quadrant + 1
        end
        if sinAngle > 0 then
            quadrant = quadrant + 2
        end

        local radius = (Minimap:GetWidth() / 2) + 5
        local x, y

        if quadTable[quadrant] then
            x = cosAngle * radius
            y = sinAngle * radius
        else
            local diagRadius = radius * 0.7071067812
            local nextQuadrant = (quadrant % 4) + 1
            local previousQuadrant = quadrant == 1 and 4 or (quadrant - 1)

            if quadTable[nextQuadrant] then
                x = cosAngle * radius
                y = sinAngle * diagRadius
            elseif quadTable[previousQuadrant] then
                x = cosAngle * diagRadius
                y = sinAngle * radius
            else
                x = cosAngle * diagRadius
                y = sinAngle * diagRadius
            end
        end

        frame:ClearAllPoints()
        frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- Handle dragging
    frame:SetScript("OnDragStart", function(self)
        self.isMoving = true
        GameTooltip:Hide()
    end)
    
    frame:SetScript("OnDragStop", function(self)
        self.isMoving = false
    end)
    
    frame:SetScript("OnUpdate", function(self)
        if self.isMoving then
            local xpos, ypos = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local mx, my = Minimap:GetCenter()
            mx = mx * scale
            my = my * scale
            
            local angle = math.deg(math.atan2(ypos - my, xpos - mx))
            PotionTrackerDB.minimapPos = (angle + 360) % 360
            UpdatePosition()
        end
    end)
    
    -- Handle mouse events
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("PotionTracker")
        GameTooltip:AddLine("Left-click: Toggle tracking")
        GameTooltip:AddLine("Right-click: Options")
        GameTooltip:Show()
    end)
    
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            ToggleTracking()
        elseif button == "RightButton" then
            ToggleDropDownMenu(1, nil, dropDown, self, 0, 0)
        end
    end)
    
    -- Initial position update
    UpdatePosition()
    
    -- Update position when minimap shape changes
    frame:RegisterEvent("MINIMAP_UPDATE_ZOOM")
    frame:SetScript("OnEvent", function()
        UpdatePosition()
    end)

    frame:SetScript("OnShow", UpdatePosition)

    self.frame = frame
    return frame
end

function UI.Options:Create()
    if optionsPanel then
        return optionsPanel
    end

    optionsPanel = CreateFrame("Frame", "PotionTrackerOptionsPanel", InterfaceOptionsFramePanelContainer or UIParent)
    optionsPanel.name = "PotionTracker"

    local LINE_SPACING = 12
    local SECTION_SPACING = 24

    local function AnchorBelow(frame, relativeTo, spacing, offsetX)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", offsetX or 0, -(spacing or LINE_SPACING))
    end

    local title = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("PotionTracker")

    local description = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    AnchorBelow(description, title, LINE_SPACING)
    description:SetWidth(360)
    description:SetJustifyH("LEFT")
    description:SetText("Adjust tracking, retention and logging without using the minimap button.")

    local trackingCheckbox = CreateFrame("CheckButton", "PotionTrackerOptionsEnableTracking", optionsPanel, WithBackdrop("InterfaceOptionsCheckButtonTemplate"))
    AnchorBelow(trackingCheckbox, description, SECTION_SPACING)
    trackingCheckbox.Text:SetText("Enable buff tracking")
    trackingCheckbox:SetScript("OnClick", function(self)
        if self:GetChecked() ~= isTracking then
            ToggleTracking()
        else
            UpdateOptionsPanel()
        end
    end)
    optionsPanel.enableTrackingCheckbox = trackingCheckbox

    local configButton = CreateFrame("Button", nil, optionsPanel, WithBackdrop("UIPanelButtonTemplate"))
    AnchorBelow(configButton, trackingCheckbox, SECTION_SPACING)
    configButton:SetSize(220, 24)
    configButton:SetText("Configure tracked buffs...")
    configButton:SetScript("OnClick", function()
        UI.BuffConfig:Show()
    end)
    optionsPanel.configButton = configButton

    local exportButton = CreateFrame("Button", nil, optionsPanel, WithBackdrop("UIPanelButtonTemplate"))
    AnchorBelow(exportButton, configButton, LINE_SPACING)
    exportButton:SetSize(220, 24)
    exportButton:SetText("Export history to CSV")
    exportButton:SetScript("OnClick", ExportCSV)
    optionsPanel.exportButton = exportButton

    local historyLabel = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    AnchorBelow(historyLabel, exportButton, SECTION_SPACING)
    historyLabel:SetText("History retention")

    local historySlider = CreateFrame("Slider", "PotionTrackerHistoryLimitSlider", optionsPanel, WithBackdrop("OptionsSliderTemplate"))
    AnchorBelow(historySlider, historyLabel, LINE_SPACING)
    historySlider:SetMinMaxValues(MIN_HISTORY_LIMIT, MAX_HISTORY_LIMIT)
    historySlider:SetValueStep(50)
    historySlider:SetObeyStepOnDrag(true)
    historySlider:SetWidth(240)
    historySlider.Text = _G[historySlider:GetName() .. "Text"]
    historySlider.Low = _G[historySlider:GetName() .. "Low"]
    historySlider.High = _G[historySlider:GetName() .. "High"]
    if historySlider.Low then historySlider.Low:SetText(tostring(MIN_HISTORY_LIMIT)) end
    if historySlider.High then historySlider.High:SetText(tostring(MAX_HISTORY_LIMIT)) end
    if historySlider.Text then
        historySlider.Text:SetText("Max history entries: " .. GetHistoryLimit())
    end
    historySlider:SetScript("OnValueChanged", function(self, value)
        if self.updating then
            return
        end

        local limit = SetHistoryLimit(value)
        if math.abs(limit - value) > 0.001 then
            self.updating = true
            self:SetValue(limit)
            self.updating = nil
        end
        if self.Text then
            self.Text:SetText("Max history entries: " .. limit)
        end
    end)
    historySlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(
            "Controls how many buff events PotionTracker keeps in memory for exports and review.",
            1, 1, 1,
            true
        )
        GameTooltip:AddLine("Higher values provide longer history but may use more memory.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    historySlider:SetScript("OnLeave", GameTooltip_Hide)
    optionsPanel.historySlider = historySlider

    local logLabel = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    AnchorBelow(logLabel, historySlider, SECTION_SPACING)
    logLabel:SetText("Log verbosity")

    local logDropdown = CreateFrame("Frame", "PotionTrackerLogLevelDropdown", optionsPanel, WithBackdrop("UIDropDownMenuTemplate"))
    AnchorBelow(logDropdown, logLabel, LINE_SPACING, -16)
    local logLevels = { "ERROR", "WARN", "INFO", "DEBUG" }
    optionsPanel.logLevelDropdown = logDropdown
    optionsPanel.logLevels = logLevels
    UIDropDownMenu_SetWidth(logDropdown, 160)
    UIDropDownMenu_Initialize(logDropdown, function(self, level)
        if not level then return end
        for _, levelKey in ipairs(logLevels) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = GetLogLevelDisplay(levelKey)
            info.value = levelKey
            info.func = function(button)
                SetActiveLogLevel(levelKey)
                UIDropDownMenu_SetSelectedValue(logDropdown, levelKey)
                if UIDropDownMenu_SetText then
                    UIDropDownMenu_SetText(logDropdown, GetLogLevelDisplay(levelKey))
                end
            end
            info.checked = (activeLogLevel == levelKey)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local logDropdownButton = _G[logDropdown:GetName() .. "Button"]
    if logDropdownButton then
        logDropdownButton:HookScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText("Select the minimum severity that will be printed to chat.", 1, 1, 1, true)
            GameTooltip:AddLine("DEBUG shows everything, while ERROR only reports critical issues.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        logDropdownButton:HookScript("OnLeave", GameTooltip_Hide)
    end

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(optionsPanel)
    end

    optionsPanel:SetScript("OnShow", function()
        UpdateOptionsPanel()
    end)
    optionsPanel.refresh = UpdateOptionsPanel
    optionsPanel.default = function()
        SetActiveLogLevel("INFO")
        SetHistoryLimit(DEFAULT_HISTORY_LIMIT)
        UpdateOptionsPanel()
    end

    self.frame = optionsPanel
    return optionsPanel
end

-- Available buffs for tracking (spell ID -> metadata)
local availableBuffs = {
    -- Protection Potions
    [17543] = { name = "Greater Fire Protection", category = "Protection Potions" },
    [17549] = { name = "Greater Arcane Protection", category = "Protection Potions" },
    [17548] = { name = "Greater Shadow Protection", category = "Protection Potions" },
    [17544] = { name = "Greater Nature Protection", category = "Protection Potions" },
    [17545] = { name = "Greater Frost Protection", category = "Protection Potions" },
    [28511] = { name = "Elixir of Major Firepower", category = "Battle Elixirs" },

    -- Defensive Potions
    [17540] = { name = "Greater Stoneshield Potion", category = "Defensive Potions" },
    [17537] = { name = "Elixir of Brute Force", category = "Battle Elixirs" },

    -- Utility Potions
    [11359] = { name = "Restoration Potion", category = "Utility Potions" },
    [6615] = { name = "Free Action Potion", category = "Utility Potions" },
    [15753] = { name = "Limited Invulnerability", category = "Utility Potions" },

    -- Flasks
    [17626] = { name = "Flask of the Titans", category = "Flasks" },
    [17627] = { name = "Flask of Supreme Power", category = "Flasks" },
    [17628] = { name = "Flask of Distilled Wisdom", category = "Flasks" },
    [17629] = { name = "Flask of Chromatic Resistance", category = "Flasks" },
}

local defaultTrackedBuffs = {
    [17543] = true,
    [17549] = true,
    [17548] = true,
    [17544] = false,
    [17545] = false,
    [17540] = true,
    [11359] = true,
    [6615] = true,
}

-- Currently tracked buffs (populated from saved variables)
local trackedBuffs = {}

local function BuildSortedBuffList()
    local list = {}
    for spellId, buff in pairs(availableBuffs) do
        table.insert(list, {
            spellId = spellId,
            name = buff.name,
            category = buff.category or "Other Buffs",
        })
    end

    table.sort(list, function(a, b)
        if a.category == b.category then
            if a.name == b.name then
                return a.spellId < b.spellId
            end
            return a.name < b.name
        end
        return a.category < b.category
    end)

    return list
end

local function GetDefaultBuffState(spellId)
    if defaultTrackedBuffs[spellId] ~= nil then
        return defaultTrackedBuffs[spellId]
    end
    return false
end

-- Function to load tracked buffs from saved variables
local function LoadTrackedBuffs()
    Debug("LoadTrackedBuffs called")
    trackedBuffs = {}

    if PotionTrackerDB and PotionTrackerDB.trackedBuffs then
        Debug("Loading from PotionTrackerDB.trackedBuffs")
        for spellId, enabled in pairs(PotionTrackerDB.trackedBuffs) do
            local buffInfo = availableBuffs[spellId]
            Debug(string.format("Spell ID %d: enabled=%s, available=%s",
                spellId, tostring(enabled), tostring(buffInfo ~= nil)))
            if enabled and buffInfo then
                trackedBuffs[spellId] = buffInfo.name
                Debug(string.format("Added %s to trackedBuffs", buffInfo.name))
            end
        end
    else
        Debug("No PotionTrackerDB.trackedBuffs found")
    end

    Debug(string.format("Loaded %d tracked buffs", GetTableSize(trackedBuffs)))
end

-- Buff configuration frame
local buffConfigFrame = nil

function UI.BuffConfig:ApplySavedPosition()
    if not buffConfigFrame then
        return
    end

    local position = PotionTrackerDB and PotionTrackerDB.buffConfigPosition
    if position and position.point then
        buffConfigFrame:ClearAllPoints()
        buffConfigFrame:SetPoint(
            position.point,
            UIParent,
            position.relativePoint or position.point,
            position.x or 0,
            position.y or 0
        )
    else
        buffConfigFrame:ClearAllPoints()
        buffConfigFrame:SetPoint("CENTER")
    end
end

function UI.BuffConfig:PersistPosition()
    if not buffConfigFrame or not buffConfigFrame:GetPoint() then
        return
    end

    local point, _, relativePoint, xOffset, yOffset = buffConfigFrame:GetPoint(1)
    if not point then
        return
    end

    if not PotionTrackerDB then
        PotionTrackerDB = {}
    end

    PotionTrackerDB.buffConfigPosition = {
        point = point,
        relativePoint = relativePoint,
        x = math.floor(xOffset + 0.5),
        y = math.floor(yOffset + 0.5),
    }
end

-- Function to create buff configuration frame (made global for access)
function UI.BuffConfig:Create()
    Debug("CreateBuffConfigFrame called")

    if buffConfigFrame then
        Debug("Buff config frame already exists")
        return buffConfigFrame
    end

    buffConfigFrame = CreateFrame("Frame", "PotionTrackerBuffConfigFrame", UIParent, WithBackdrop("DialogBoxFrame"))

    -- Basic frame setup
    buffConfigFrame:SetSize(400, 500)
    self:ApplySavedPosition()
    buffConfigFrame:SetFrameStrata("HIGH")
    buffConfigFrame:SetFrameLevel(1000)
    buffConfigFrame:SetMovable(true)
    buffConfigFrame:EnableMouse(true)
    buffConfigFrame:EnableKeyboard(true)
    buffConfigFrame:RegisterForDrag("LeftButton")

    buffConfigFrame:SetScript("OnDragStart", function(self)
        if self.StartMoving then
            self:StartMoving()
        end
    end)
    buffConfigFrame:SetScript("OnDragStop", function(self)
        if self.StopMovingOrSizing then
            self:StopMovingOrSizing()
        end
        UI.BuffConfig:PersistPosition()
    end)

    -- Title
    local title = buffConfigFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("PotionTracker - Buff Configuration")
    title:SetTextColor(1, 1, 1, 1) -- White text

    -- Close button
    local closeButton = CreateFrame("Button", nil, buffConfigFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 2, 2)
    closeButton:SetScript("OnClick", function()
        buffConfigFrame:Hide()
    end)

    -- Scrollable buff list
    local scrollFrame = CreateFrame("ScrollFrame", "PotionTrackerBuffScrollFrame", buffConfigFrame, WithBackdrop("UIPanelScrollFrameTemplate"))
    scrollFrame:SetPoint("TOPLEFT", 20, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", -45, 90)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    local sortedBuffs = BuildSortedBuffList()
    local yOffset = 0
    local currentCategory = nil
    local checkboxes = {}

    for _, buff in ipairs(sortedBuffs) do
        if buff.category ~= currentCategory then
            currentCategory = buff.category
            local header = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            header:SetPoint("TOPLEFT", 0, yOffset)
            header:SetText(currentCategory)
            header:SetTextColor(1, 0.82, 0)
            header:SetJustifyH("LEFT")
            yOffset = yOffset - 20
        end

        local checkbox = CreateFrame("CheckButton", nil, content)
        checkbox:SetPoint("TOPLEFT", 0, yOffset)
        checkbox:SetSize(24, 24)

        local normal = checkbox:CreateTexture(nil, "ARTWORK")
        normal:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        normal:SetAllPoints()
        checkbox:SetNormalTexture(normal)

        local checked = checkbox:CreateTexture(nil, "ARTWORK")
        checked:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checked:SetAllPoints()
        checkbox:SetCheckedTexture(checked)

        local isChecked = GetDefaultBuffState(buff.spellId)
        if PotionTrackerDB and PotionTrackerDB.trackedBuffs then
            local savedValue = PotionTrackerDB.trackedBuffs[buff.spellId]
            if savedValue ~= nil then
                isChecked = savedValue
            end
        end
        checkbox:SetChecked(isChecked)
        checkbox.initialState = isChecked

        local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", checkbox, "RIGHT", 10, 0)
        label:SetText(buff.name)
        label:SetJustifyH("LEFT")
        label:SetTextColor(1, 1, 1, 1)
        label:SetWidth(250)
        label:SetWordWrap(false)

        checkboxes[buff.spellId] = checkbox
        yOffset = yOffset - 28
    end

    content:SetWidth(280)
    content:SetHeight(math.max(1, -yOffset))

    -- Store checkboxes for later use
    buffConfigFrame.checkboxes = checkboxes

    local statusText = buffConfigFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOM", 0, 60)
    statusText:SetWidth(280)
    statusText:SetJustifyH("CENTER")

    -- Save and reset buttons
    local saveButton = CreateFrame("Button", nil, buffConfigFrame, WithBackdrop("UIPanelButtonTemplate"))
    saveButton:SetSize(120, 26)
    saveButton:SetPoint("BOTTOMLEFT", 20, 20)
    saveButton:SetText("Save")

    local resetButton = CreateFrame("Button", nil, buffConfigFrame, WithBackdrop("UIPanelButtonTemplate"))
    resetButton:SetSize(120, 26)
    resetButton:SetPoint("BOTTOMRIGHT", -20, 20)
    resetButton:SetText("Reset")

    local function UpdateChangeState(message, r, g, b)
        local hasChanges = false
        for _, checkbox in pairs(checkboxes) do
            if checkbox:GetChecked() ~= checkbox.initialState then
                hasChanges = true
                break
            end
        end

        if hasChanges then
            saveButton:Enable()
            statusText:SetText(message or "Unsaved changes")
            statusText:SetTextColor(r or 1, g or 0.82, b or 0)
        else
            saveButton:Disable()
            statusText:SetText(message or "No pending changes")
            statusText:SetTextColor(r or 0.7, g or 0.9, b or 0.7)
        end

        buffConfigFrame.hasPendingChanges = hasChanges
    end

    buffConfigFrame.UpdateChangeState = UpdateChangeState

    function buffConfigFrame:ResetInitialStates(message, r, g, b)
        for _, checkbox in pairs(self.checkboxes) do
            checkbox.initialState = checkbox:GetChecked()
        end
        UpdateChangeState(message, r, g, b)
    end

    for _, checkbox in pairs(checkboxes) do
        checkbox:SetScript("OnClick", function()
            UpdateChangeState()
        end)
    end

    saveButton:SetScript("OnClick", function()
        if not PotionTrackerDB.trackedBuffs then
            PotionTrackerDB.trackedBuffs = {}
        end

        for spellId, checkbox in pairs(checkboxes) do
            PotionTrackerDB.trackedBuffs[spellId] = checkbox:GetChecked()
            checkbox.initialState = checkbox:GetChecked()
        end

        LoadTrackedBuffs()

        PlayUISound("IG_MAINMENU_OPTION_CHECKBOX_ON", "igMainMenuOptionCheckBoxOn")
        Print("Buff configuration saved!")
        UpdateChangeState("Changes saved", 0.7, 0.9, 0.7)
    end)

    resetButton:SetScript("OnClick", function()
        for spellId, checkbox in pairs(checkboxes) do
            checkbox:SetChecked(GetDefaultBuffState(spellId))
        end

        PlayUISound("IG_MAINMENU_OPTION_CHECKBOX_ON", "igMainMenuOptionCheckBoxOn")
        UpdateChangeState("Defaults restored (save to apply)", 1, 0.82, 0)
    end)

    buffConfigFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
        end
    end)

    buffConfigFrame:SetScript("OnShow", function()
        PlayUISound("IG_MAINMENU_OPEN", "igMainMenuOpen")
        UpdateChangeState()
    end)

    buffConfigFrame:SetScript("OnHide", function()
        PlayUISound("IG_MAINMENU_CLOSE", "igMainMenuClose")
    end)

    UpdateChangeState("No pending changes", 0.7, 0.9, 0.7)

    Debug("Buff config frame creation completed")
    self.frame = buffConfigFrame
    return buffConfigFrame
end

function UI.BuffConfig:Show()
    Debug("ShowBuffConfigFrame called")

    if not buffConfigFrame then
        Debug("Creating buff config frame")
        self:Create()
    end

    if not buffConfigFrame then
        Print("Failed to create buff configuration frame", "ERROR")
        return
    end

    self:ApplySavedPosition()

    Debug("Buff config frame exists, showing")
    
    -- Update checkbox states from current settings
    if PotionTrackerDB and PotionTrackerDB.trackedBuffs and buffConfigFrame.checkboxes then
        for spellId, checkbox in pairs(buffConfigFrame.checkboxes) do
            local saved = PotionTrackerDB.trackedBuffs[spellId]
            if saved == nil then
                checkbox:SetChecked(GetDefaultBuffState(spellId))
            else
                checkbox:SetChecked(saved)
            end
        end
    end

    if buffConfigFrame.ResetInitialStates then
        buffConfigFrame:ResetInitialStates("No pending changes", 0.7, 0.9, 0.7)
    end

    -- Show the frame
    buffConfigFrame:Show()
    
    Debug("Buff config frame should now be visible")
    Print("Buff configuration window opened")
end

-- Table of tracked mobs/bosses
local trackedMobs = {
    -- Molten Core
    ["Lucifron"] = true,
    ["Magmadar"] = true,
    ["Gehennas"] = true,
    ["Garr"] = true,
    ["Baron Geddon"] = true,
    ["Shazzrah"] = true,
    ["Sulfuron Harbinger"] = true,
    ["Golemagg the Incinerator"] = true,
    ["Majordomo Executus"] = true,
    ["Ragnaros"] = true,
    
    -- Onyxia
    ["Onyxia"] = true,
    
    -- Blackwing Lair
    ["Razorgore the Untamed"] = true,
    ["Vaelastrasz the Corrupt"] = true,
    ["Broodlord Lashlayer"] = true,
    ["Firemaw"] = true,
    ["Ebonroc"] = true,
    ["Flamegor"] = true,
    ["Chromaggus"] = true,
    ["Nefarian"] = true,

    -- Zul'Gurub
    ["High Priest Venoxis"] = true,
    ["High Priestess Jeklik"] = true,
    ["High Priestess Mar'li"] = true,
    ["High Priest Thekal"] = true,
    ["High Priestess Arlokk"] = true,
    ["Bloodlord Mandokir"] = true,
    ["Jin'do the Hexxer"] = true,
    ["Gahz'ranka"] = true,
    ["Hakkar"] = true,

    -- Ruins of Ahn'Qiraj
    ["Kurinnaxx"] = true,
    ["General Rajaxx"] = true,
    ["Moam"] = true,
    ["Buru the Gorger"] = true,
    ["Ayamiss the Hunter"] = true,
    ["Ossirian the Unscarred"] = true,

    -- Temple of Ahn'Qiraj
    ["The Prophet Skeram"] = true,
    ["Lord Kri"] = true,
    ["Princess Yauj"] = true,
    ["Vem"] = true,
    ["Battleguard Sartura"] = true,
    ["Fankriss the Unyielding"] = true,
    ["Viscidus"] = true,
    ["Princess Huhuran"] = true,
    ["Emperor Vek'lor"] = true,
    ["Emperor Vek'nilash"] = true,
    ["Ouro"] = true,
    ["C'Thun"] = true,

    -- Naxxramas
    ["Anub'Rekhan"] = true,
    ["Grand Widow Faerlina"] = true,
    ["Maexxna"] = true,
    ["Noth the Plaguebringer"] = true,
    ["Heigan the Unclean"] = true,
    ["Loatheb"] = true,
    ["Instructor Razuvious"] = true,
    ["Gothik the Harvester"] = true,
    ["Thane Korth'azz"] = true,
    ["Lady Blaumeux"] = true,
    ["Sir Zeliek"] = true,
    ["Baron Rivendare"] = true,
    ["Patchwerk"] = true,
    ["Grobbulus"] = true,
    ["Gluth"] = true,
    ["Thaddius"] = true,
    ["Sapphiron"] = true,
    ["Kel'Thuzad"] = true,

    -- World bosses
    ["Azuregos"] = true,
    ["Lord Kazzak"] = true,
    ["Emeriss"] = true,
    ["Lethon"] = true,
    ["Taerar"] = true,
    ["Ysondre"] = true,
}

-- Throttle for buff updates (prevent spam)
local lastUnitUpdate = {}
local UPDATE_THROTTLE = 0.05 -- seconds

-- Function to get unit's tracked buffs (optimized)
local function GetUnitBuffs(unit)
    local buffs = {}
    local i = 1
    local name, _, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
    
    while name do
        -- Check if this buff's spell ID matches any of our tracked buffs
        if trackedBuffs[spellId] then
            buffs[trackedBuffs[spellId]] = {
                duration = duration,
                expirationTime = expirationTime
            }
        end
        i = i + 1
        name, _, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
    end
    
    return buffs
end

-- Function to initialize buff tracking for a unit
local function InitializeUnitBuffs(unit)
    if not UnitExists(unit) then
        Debug("Unit does not exist: " .. tostring(unit))
        return
    end

    local unitName = UnitName(unit)
    if not unitName then
        Debug("Could not get unit name for: " .. tostring(unit))
        return
    end

    Debug("Checking buffs for " .. unitName)

    lastUnitUpdate[unit] = 0

    -- Check each tracked buff directly
    for spellId, buffName in pairs(trackedBuffs) do
        local auraName = GetSpellInfo(spellId) or buffName
        Debug("Checking for buff: " .. tostring(auraName))
        local name, _, _, _, duration = AuraUtil.FindAuraByName(auraName, unit, "HELPFUL")
        if name then
            Debug("Found tracked buff at load: " .. name)

            -- Print to chat
            local timeStr = ""
            if duration and duration > 0 then
                local minutes = math.floor(duration / 60)
                local seconds = duration % 60
                timeStr = string.format(" (%dm %ds)", minutes, seconds)
            end
            Print(unitName .. " has " .. name .. timeStr)

            -- Record the event immediately
            local timestamp = time()
            local entry = {
                timestamp = timestamp,
                date = date("%Y-%m-%d %H:%M:%S", timestamp),
                unit = unitName,
                buff = name,
                event = "BUFF_GAINED",
                duration = duration or 0
            }

            -- Add directly to history
            if not buffHistory then buffHistory = {} end
            table.insert(buffHistory, entry)
            if not PotionTrackerDB then PotionTrackerDB = {} end
            PotionTrackerDB.buffHistory = buffHistory
            EnforceHistoryLimit()
            Debug("History size after initializing buff: " .. #buffHistory)
        end
    end
    
    -- Store current state for future comparisons
    previousBuffs[unit] = GetUnitBuffs(unit)
end

-- Function to add event to history
local function AddToHistory(event)
    if not buffHistory then buffHistory = {} end
    table.insert(buffHistory, event)
    -- Ensure we save to PotionTrackerDB
    if not PotionTrackerDB then PotionTrackerDB = {} end
    PotionTrackerDB.buffHistory = buffHistory
    EnforceHistoryLimit()
    Debug("Current history size: " .. #buffHistory)
end

-- Function to record buff event
local function RecordBuffEvent(unitName, buffName, eventType, duration)
    Debug("Recording buff event: " .. eventType .. " - " .. buffName)
    local timestamp = time()
    local entry = {
        timestamp = timestamp,
        date = date("%Y-%m-%d %H:%M:%S", timestamp),
        unit = unitName,
        buff = buffName,
        event = eventType,
        duration = duration or 0
    }
    
    -- Add to history
    AddToHistory(entry)
    
    -- Print buff info
    if eventType == "BUFF_GAINED" then
        local timeLeft = ""
        if duration and duration > 0 then
            local minutes = math.floor(duration / 60)
            local seconds = duration % 60
            timeLeft = string.format(" (%dm %ds)", minutes, seconds)
        end
        Print(unitName .. " gained " .. buffName .. timeLeft)
    elseif eventType == "BUFF_LOST" then
        Print(unitName .. " lost " .. buffName)
    end
end

-- Function to check for new buffs (optimized)
local function CheckNewBuffs(unit)
    if not UnitExists(unit) then return end
    
    -- Throttle updates
    local currentTime = GetTime()
    local previousUpdate = lastUnitUpdate[unit] or 0
    if currentTime - previousUpdate < UPDATE_THROTTLE then return end
    lastUnitUpdate[unit] = currentTime
    
    local unitName = UnitName(unit)
    local currentBuffs = GetUnitBuffs(unit)
    
    -- Initialize previous buffs for this unit if needed
    previousBuffs[unit] = previousBuffs[unit] or {}
    
    -- Check for new buffs (only tracked ones)
    for buffName, buffInfo in pairs(currentBuffs) do
        if not previousBuffs[unit][buffName] then
            RecordBuffEvent(unitName, buffName, "BUFF_GAINED", buffInfo.duration)
        end
    end
    
    -- Check for removed buffs (only tracked ones)
    for buffName in pairs(previousBuffs[unit]) do
        if not currentBuffs[buffName] then
            RecordBuffEvent(unitName, buffName, "BUFF_LOST", 0)
        end
    end
    
    -- Update previous buffs
    previousBuffs[unit] = currentBuffs
end

-- Function to check appropriate units based on group state
function UI.Options:Refresh()
    if not optionsPanel then return end

    if optionsPanel.enableTrackingCheckbox then
        optionsPanel.enableTrackingCheckbox:SetChecked(isTracking)
    end

    if optionsPanel.historySlider then
        local limit = GetHistoryLimit()
        optionsPanel.historySlider.updating = true
        optionsPanel.historySlider:SetValue(limit)
        optionsPanel.historySlider.updating = nil
        if optionsPanel.historySlider.Text then
            optionsPanel.historySlider.Text:SetText("Max history entries: " .. limit)
        end
    end

    if optionsPanel.logLevelDropdown then
        UIDropDownMenu_SetSelectedValue(optionsPanel.logLevelDropdown, activeLogLevel)
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(optionsPanel.logLevelDropdown, GetLogLevelDisplay(activeLogLevel))
        end
    end
end

local function UpdateOptionsPanel()
    UI.Options:Refresh()
end

local function OpenOptionsInterface()
    local panel = UI.Options:Create()
    if InterfaceOptionsFrame_OpenToCategory and panel then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
        return
    end

    if Settings and Settings.OpenToCategory and panel and panel.name then
        Settings.OpenToCategory(panel.name)
        return
    end

    UI.BuffConfig:Show()
end

local function CheckAppropriateUnits(unit)
    -- Always check if it's the player
    if unit == "player" then
        CheckNewBuffs("player")
        return
    end
    
    -- For party/raid members, only check if the unit is valid for our current group type
    if IsInRaid() then
        -- In raid, check raid units
        if unit:find("^raid%d+$") then
            CheckNewBuffs(unit)
        end
    elseif IsInGroup() then
        -- In party, check party units
        if unit:find("^party%d+$") then
            CheckNewBuffs(unit)
        end
    end
end

-- Function to update icon appearance
function UI.Minimap:UpdateIconState()
    if not minimapIcon then return end
    if isTracking then
        minimapIcon.texture:SetDesaturated(false)
    else
        minimapIcon.texture:SetDesaturated(true)
    end
end

-- Track current group members
local currentGroupMembers = {}

-- Function to get current group member list
local function GetCurrentGroupMembers()
    local members = {}
    
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetUnitName("raid" .. i, true)
            if name then
                members[name] = "raid" .. i
            end
        end
    elseif IsInGroup() then
        -- Add player first
        local playerName = GetUnitName("player", true)
        members[playerName] = "player"
        
        for i = 1, GetNumSubgroupMembers() do
            local name = GetUnitName("party" .. i, true)
            if name then
                members[name] = "party" .. i
            end
        end
    else
        -- Solo player
        local playerName = GetUnitName("player", true)
        members[playerName] = "player"
    end
    
    return members
end

-- Function to initialize all appropriate units
InitializeAllUnits = function()
    Debug("Initializing buff tracking")
    
    -- Always check player
    InitializeUnitBuffs("player")
    
    -- Check party members if in a party
    if IsInGroup() and not IsInRaid() then
        for i = 1, GetNumSubgroupMembers() do
            InitializeUnitBuffs("party" .. i)
        end
    end
    
    -- Check raid members if in a raid
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            InitializeUnitBuffs("raid" .. i)
        end
    end
    
    -- Store current group state
    currentGroupMembers = GetCurrentGroupMembers()
end

-- Combat tracking variables
local inCombat = false
local currentTarget = nil
local combatStartTime = nil
local combatTargets = {}
local combatTarget = nil  -- Primary target when combat started
local encounterCounter = 0
local activeEncounterId = nil

-- Function to get target info
local function GetTargetInfo()
    if not UnitExists("target") then return nil end
    
    local name = UnitName("target")
    -- Only return info if it's a tracked mob
    if not trackedMobs[name] then return nil end
    
    local level = UnitLevel("target")
    local classification = UnitClassification("target")
    local isElite = classification == "elite" or classification == "rareelite"
    local guid = UnitGUID("target")

    return {
        name = name,
        level = level,
        classification = classification,
        isElite = isElite,
        guid = guid
    }
end

local function GetCombatTargetsSnapshot()
    local snapshot = {}
    for _, data in pairs(combatTargets) do
        table.insert(snapshot, {
            name = data.name,
            level = data.level,
            classification = data.classification,
            isElite = data.isElite,
            firstSeen = data.firstSeen,
        })
    end

    table.sort(snapshot, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    return snapshot
end

-- Function to record combat event
local function RecordCombatEvent(eventType, target)
    local targetName = target and target.name or nil
    if targetName and not trackedMobs[targetName] then
        Debug("Ignoring combat event for untracked target: " .. targetName)
        return
    end

    local eventInfo = {
        timestamp = time(),
        event = eventType,
        encounterId = activeEncounterId,
        targetName = targetName,
        targetLevel = target and target.level or nil,
        targetClassification = target and target.classification or nil,
    }

    eventInfo.date = date("%Y-%m-%d %H:%M:%S", eventInfo.timestamp)

    if eventType == "COMBAT_END" then
        eventInfo.duration = time() - (combatStartTime or time())
        eventInfo.targets = GetCombatTargetsSnapshot()
        eventInfo.targetCount = eventInfo.targets and #eventInfo.targets or 0
    end

    -- Add to history
    AddToHistory(eventInfo)

    -- Print combat info
    if eventType == "COMBAT_START" then
        if targetName then
            Print(string.format("Entered combat with %s (Level %s%s) [Encounter %d]",
                targetName,
                tostring(target and target.level or "?"),
                target and target.isElite and " Elite" or "",
                activeEncounterId or 0))
        else
            Print(string.format("Entered combat [Encounter %d]", activeEncounterId or 0))
        end
    elseif eventType == "COMBAT_END" then
        local countText = eventInfo.targetCount and eventInfo.targetCount > 0 and string.format(" involving %d target(s)", eventInfo.targetCount) or ""
        Print(string.format("Left combat%s after %d seconds [Encounter %d]",
            countText,
            eventInfo.duration or 0,
            activeEncounterId or 0))
    elseif eventType == "COMBAT_TARGET_ADDED" and targetName then
        Print(string.format("Tracking combat target: %s", targetName))
    end
end

local function AddCombatTarget(target)
    if not inCombat then return end
    if not target or not target.name or not trackedMobs[target.name] then return end

    local key = target.guid or target.name
    if not combatTargets[key] then
        combatTargets[key] = {
            name = target.name,
            level = target.level,
            classification = target.classification,
            isElite = target.isElite,
            firstSeen = time(),
        }
        if not combatTarget then
            combatTarget = target
        end
        RecordCombatEvent("COMBAT_TARGET_ADDED", target)
    end
end

local function ResetCombatState()
    inCombat = false
    combatStartTime = nil
    combatTarget = nil
    activeEncounterId = nil
    combatTargets = {}
    currentTarget = nil
end

-- Event handler
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Initialize saved variables
        PotionTrackerDB = PotionTrackerDB or {}
        PotionTrackerDB.minimapPos = PotionTrackerDB.minimapPos or 45
        PotionTrackerDB.isTracking = PotionTrackerDB.isTracking or false
        PotionTrackerDB.buffHistory = PotionTrackerDB.buffHistory or {}
        PotionTrackerDB.trackedBuffs = PotionTrackerDB.trackedBuffs or {}

        for spellId in pairs(availableBuffs) do
            if PotionTrackerDB.trackedBuffs[spellId] == nil then
                PotionTrackerDB.trackedBuffs[spellId] = GetDefaultBuffState(spellId)
            end
        end

        if PotionTrackerDB.logLevel then
            if not SetActiveLogLevel(PotionTrackerDB.logLevel) then
                SetActiveLogLevel("INFO")
            end
        else
            SetActiveLogLevel(activeLogLevel)
        end
        Debug("Active log level: " .. activeLogLevel)

        -- Load saved buff history
        buffHistory = PotionTrackerDB.buffHistory or {}
        EnforceHistoryLimit()

        -- Load tracked buffs from saved variables
        LoadTrackedBuffs()
        
        -- Create minimap icon
        minimapIcon = UI.Minimap:Create()

        -- Set initial tracking state
        isTracking = PotionTrackerDB.isTracking
        UI.Minimap:UpdateIconState()

        -- Create Interface Options panel for easier access
        UI.Options:Create()
        UpdateOptionsPanel()
        
        -- Initialize buff tracking if it was enabled
        if isTracking then
            InitializeAllUnits()
        end
        
    elseif event == "UNIT_AURA" then
        if not isTracking then return end
        local unit = ...
        CheckAppropriateUnits(unit)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not isTracking then return end
        
        -- Get new group state
        local newGroupMembers = GetCurrentGroupMembers()
        
        -- Find new members
        for name, unit in pairs(newGroupMembers) do
            if not currentGroupMembers[name] then
                Debug("New member joined: " .. name)
                InitializeUnitBuffs(unit)
            end
        end
        
        -- Update current group state
        currentGroupMembers = newGroupMembers
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat
        if not isTracking then return end

        inCombat = true
        encounterCounter = encounterCounter + 1
        activeEncounterId = encounterCounter
        combatStartTime = time()
        combatTargets = {}

        local target = GetTargetInfo()
        if target then
            local key = target.guid or target.name
            combatTarget = target
            combatTargets[key] = {
                name = target.name,
                level = target.level,
                classification = target.classification,
                isElite = target.isElite,
                firstSeen = time(),
            }
        else
            combatTarget = nil
        end

        RecordCombatEvent("COMBAT_START", combatTarget)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat
        if not isTracking or not combatStartTime then return end

        RecordCombatEvent("COMBAT_END", combatTarget)
        ResetCombatState()

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Update current target info
        if isTracking then
            currentTarget = GetTargetInfo()
            if inCombat and currentTarget then
                AddCombatTarget(currentTarget)
            end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, combatEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId = CombatLogGetCurrentEventInfo()

        -- Only process certain events
        if combatEvent == "SPELL_AURA_APPLIED" then
            -- Check if this is a tracked buff
            if trackedBuffs[spellId] and destGUID and destGUID:find("^Player") then
                RecordBuffEvent(destName or "Unknown", trackedBuffs[spellId], "BUFF_GAINED", 0)
            end
        end

        if inCombat and destName and trackedMobs[destName] then
            AddCombatTarget({ name = destName, guid = destGUID })
        end
    end
end)

-- Slash command
SLASH_POTIONTRACKER1 = "/pt"
SLASH_POTIONTRACKER2 = "/potiontracker"
SlashCmdList["POTIONTRACKER"] = function(msg)
    msg = msg or ""
    msg = strtrim(msg)
    local command, argument = msg:match("^(%S+)%s*(.*)$")
    command = string.lower(command or "")
    argument = strtrim(argument or "")

    if command == "" or command == "help" then
        Print("Commands:")
        Print("/pt toggle - Toggle buff tracking")
        Print("/pt config - Configure tracked buffs")
        Print("/pt options - Open addon options (falls back to buff list)")
        Print("/pt export - Export buff history (saves on logout)")
        Print("/pt clear - Clear buff history without reloading")
        Print("/pt stats - Show tracking statistics")
        Print("/pt reload - Reload tracked buffs")
        Print("/pt hidetest - Hide test frame")
        Print("/pt log [level] - View or set log level")
        Print("/pt showcsv - Display CSV data in chat (if file export failed)")
        return
    end

    if command == "toggle" then
        ToggleTracking()
    elseif command == "config" or command == "buffs" then
        Debug("Slash command: config")
        UI.BuffConfig:Show()
    elseif command == "options" or command == "settings" then
        OpenOptionsInterface()
    elseif command == "export" then
        ExportCSV()
        Debug("Slash command: export")
    elseif command == "clear" then
        PotionTrackerDB.buffHistory = {}
        buffHistory = {}
        PotionTrackerDB.exportedCSV = nil
        Print("History cleared. Fresh data will be saved going forward.")
    elseif command == "stats" then
        local count = #(PotionTrackerDB.buffHistory or {})
        Print(string.format("Tracking %d buff events", count))
        if ShouldLog("DEBUG") then
            Print("Detailed stats available in debug log level", "DEBUG")
            Print("isTracking: " .. tostring(isTracking), "DEBUG")
            Print("trackedBuffs count: " .. tostring(GetTableSize(trackedBuffs)), "DEBUG")
            Print("Available buffs:", "DEBUG")
            for spellId, buffInfo in pairs(availableBuffs) do
                local isTracked = trackedBuffs[spellId] ~= nil
                local isEnabled = PotionTrackerDB and PotionTrackerDB.trackedBuffs and PotionTrackerDB.trackedBuffs[spellId]
                Print(string.format("  %s (ID: %d) - Tracked: %s, Enabled: %s",
                    buffInfo.name, spellId, tostring(isTracked), tostring(isEnabled)), "DEBUG")
            end
        end
    elseif command == "hidetest" then
        if _G.PotionTrackerTestFrame then
            _G.PotionTrackerTestFrame:Hide()
            Print("Test frame hidden")
        end
    elseif command == "reload" then
        LoadTrackedBuffs()
        Print("Reloaded tracked buffs")
    elseif command == "log" then
        if argument == "" then
            Print("Current log level: " .. activeLogLevel)
        else
            if SetActiveLogLevel(argument) then
                Print("Log level set to " .. activeLogLevel)
                UpdateOptionsPanel()
            else
                Print("Invalid log level. Use: error, warn, info, debug.", "WARN")
            end
        end
    elseif command == "showcsv" then
        if PotionTrackerDB and PotionTrackerDB.exportedCSV then
            Print("=== POTIONTRACKER CSV EXPORT ===")
            Print("Copy the data below and save it as a .csv file:")
            Print("")
            
            -- Split CSV into lines and print each one
            local lines = {}
            for line in PotionTrackerDB.exportedCSV:gmatch("[^\r\n]+") do
                table.insert(lines, line)
            end
            
            for i, line in ipairs(lines) do
                Print(line)
            end
            
            Print("")
            Print("=== END CSV DATA ===")
            Print("Total lines: " .. #lines)
            Print("Save this data as PotionTracker_Export.csv")
        else
            Print("No CSV data found in SavedVariables.")
            Print("Run /pt export first to generate CSV data.")
        end
    else
        Print("Unknown command. Type /pt help for options.", "WARN")
    end
end
