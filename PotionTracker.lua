-- Create main addon frame
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Entering combat
f:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leaving combat
f:RegisterEvent("PLAYER_TARGET_CHANGED")  -- Target changed
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")  -- Add combat log event

-- Function to print messages (moved outside local scope)
Print = function(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00PotionTracker|r: " .. msg)
end

-- Helper function to get table size
GetTableSize = function(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Function to export history as CSV (moved outside local scope)
ExportCSV = function()
    if not PotionTrackerDB or not PotionTrackerDB.buffHistory or #PotionTrackerDB.buffHistory == 0 then
        Print("No events to export")
        return
    end
    
    -- Create CSV header
    local csv = "Timestamp,Event,Unit,Buff,Target,Duration\n"
    
    -- Add each event
    for _, event in ipairs(PotionTrackerDB.buffHistory) do
        local timestamp = event.date or date("%Y-%m-%d %H:%M:%S", event.timestamp)
        -- Escape any commas in the fields
        local function escape(str)
            if str and str:find(",") then
                return '"' .. str .. '"'
            end
            return str
        end

        -- Combine fields into CSV line
        local line = string.format("%s,%s,%s,%s,%s,%s\n",
            escape(timestamp),
            escape(event.event or ""),
            escape(event.unit or ""),
            escape(event.buff or ""),
            escape(event.targetName or ""),
            escape(event.duration and tostring(event.duration) or "")
        )

        csv = csv .. line
    end

    -- Save formatted CSV to SavedVariables
    PotionTrackerDB.exportedCSV = csv
    Print("CSV export ready. Data will be saved automatically on logout.")
end

-- Initialize variables
local isTracking = false
local minimapIcon = nil
local buffHistory = {}
local previousBuffs = {}
local dropDown = nil  -- Move dropDown to global scope

-- Forward declarations
local InitializeAllUnits

-- Function to toggle tracking
local function ToggleTracking()
    isTracking = not isTracking

    if not PotionTrackerDB then
        PotionTrackerDB = {}
    end
    PotionTrackerDB.isTracking = isTracking

    if isTracking then
        Print("Tracking started")
        if minimapIcon and minimapIcon.texture then
            minimapIcon.texture:SetDesaturated(false)
        end

        -- Reset cached buff state and scan current units so we don't miss existing buffs
        previousBuffs = {}
        InitializeAllUnits()
    else
        Print("Tracking stopped")
        if minimapIcon and minimapIcon.texture then
            minimapIcon.texture:SetDesaturated(true)
        end
    end
end

-- Create dropdown menu
local function InitializeMenu(frame, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    
    info.text = "PotionTracker Options"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()  -- Reset info table for next button
    info.notCheckable = true
    info.text = "Configure Buffs"
    info.func = function()
        Print("Configure Buffs clicked!")
        ShowBuffConfigFrame()
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()  -- Reset info table for next button
    info.notCheckable = true
    info.text = "Export Data"
    info.func = function()
        ExportCSV()
        Print("Export complete. Logout to persist immediately if desired.")
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
local function CreateMinimapIcon()
    local frame = CreateFrame("Button", "PotionTrackerMinimapIcon", Minimap)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    frame:SetMovable(false)
    
    -- Set size and position
    frame:SetWidth(32)
    frame:SetHeight(32)
    frame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
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
        dropDown = CreateFrame("Frame", "PotionTrackerDropDownMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(dropDown, InitializeMenu)
    
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:RegisterForDrag("LeftButton")
    
    -- Minimap icon positioning
    local function UpdatePosition()
        local angle = math.rad(PotionTrackerDB.minimapPos or 45)
        local cos = math.cos(angle)
        local sin = math.sin(angle)
        local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
        
        -- Get the minimap size
        local minimapWidth = Minimap:GetWidth() / 2
        local minimapHeight = Minimap:GetHeight() / 2
        
        -- Adjust position based on shape
        local w = minimapWidth * 0.75
        local h = minimapHeight * 0.75
        
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", Minimap, "CENTER", w * cos, h * sin)
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
            PotionTrackerDB.minimapPos = angle
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
    
    return frame
end

-- Available buffs for tracking (spell ID -> display name)
local availableBuffs = {
    -- Protection Potions
    [17543] = "Greater Fire Protection",
    [17549] = "Greater Arcane Protection", 
    [17548] = "Greater Shadow Protection",
    [17544] = "Greater Nature Protection",
    [17545] = "Greater Frost Protection",
    
    -- Other Potions
    [11359] = "Greater Restoration",
    [6615] = "Free Action",
}

-- Currently tracked buffs (populated from saved variables)
local trackedBuffs = {}

-- Function to load tracked buffs from saved variables
local function LoadTrackedBuffs()
    Print("LoadTrackedBuffs called!")
    trackedBuffs = {}
    
    if PotionTrackerDB and PotionTrackerDB.trackedBuffs then
        Print("Loading from PotionTrackerDB.trackedBuffs...")
        for spellId, enabled in pairs(PotionTrackerDB.trackedBuffs) do
            Print(string.format("  Spell ID %d: enabled=%s, available=%s", 
                spellId, tostring(enabled), tostring(availableBuffs[spellId] ~= nil)))
            if enabled and availableBuffs[spellId] then
                trackedBuffs[spellId] = availableBuffs[spellId]
                Print(string.format("  Added %s to trackedBuffs", availableBuffs[spellId]))
            end
        end
    else
        Print("No PotionTrackerDB.trackedBuffs found!")
    end
    
    Print(string.format("Loaded %d tracked buffs", GetTableSize(trackedBuffs)))
end

-- Buff configuration frame
local buffConfigFrame = nil

-- Function to create buff configuration frame (made global for access)
CreateBuffConfigFrame = function()
    Print("CreateBuffConfigFrame called!")
    
    if buffConfigFrame then
        Print("Buff config frame already exists, returning it")
        return buffConfigFrame
    end
    
    Print("Creating new buff config frame...")
    
    -- Create main frame - SIMPLIFIED for Classic Era compatibility
    buffConfigFrame = CreateFrame("Frame", "PotionTrackerBuffConfigFrame", UIParent)
    Print("Frame created: " .. tostring(buffConfigFrame ~= nil))
    
    -- Basic frame setup
    buffConfigFrame:SetSize(400, 500)
    buffConfigFrame:SetPoint("CENTER")
    buffConfigFrame:SetFrameStrata("HIGH")
    buffConfigFrame:SetFrameLevel(1000)
    
    -- Simple background using a texture instead of backdrop
    local bg = buffConfigFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.9) -- Dark gray background
    
    -- Border using multiple textures
    local borderTop = buffConfigFrame:CreateTexture(nil, "BORDER")
    borderTop:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Border")
    borderTop:SetPoint("TOPLEFT", -16, 16)
    borderTop:SetPoint("TOPRIGHT", 16, 16)
    borderTop:SetHeight(16)
    borderTop:SetTexCoord(0, 1, 0, 0.25)
    
    local borderBottom = buffConfigFrame:CreateTexture(nil, "BORDER")
    borderBottom:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Border")
    borderBottom:SetPoint("BOTTOMLEFT", -16, -16)
    borderBottom:SetPoint("BOTTOMRIGHT", 16, -16)
    borderBottom:SetHeight(16)
    borderBottom:SetTexCoord(0, 1, 0.75, 1)
    
    local borderLeft = buffConfigFrame:CreateTexture(nil, "BORDER")
    borderLeft:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Border")
    borderLeft:SetPoint("TOPLEFT", -16, 16)
    borderLeft:SetPoint("BOTTOMLEFT", -16, -16)
    borderLeft:SetWidth(16)
    borderLeft:SetTexCoord(0, 0.25, 0, 1)
    
    local borderRight = buffConfigFrame:CreateTexture(nil, "BORDER")
    borderRight:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Border")
    borderRight:SetPoint("TOPRIGHT", 16, 16)
    borderRight:SetPoint("BOTTOMRIGHT", 16, -16)
    borderRight:SetWidth(16)
    borderRight:SetTexCoord(0.75, 1, 0, 1)
    
    -- Make frame draggable
    buffConfigFrame:SetMovable(true)
    buffConfigFrame:EnableMouse(true)
    buffConfigFrame:RegisterForDrag("LeftButton")
    buffConfigFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    buffConfigFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    
    -- Title
    local title = buffConfigFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("PotionTracker - Buff Configuration")
    title:SetTextColor(1, 1, 1, 1) -- White text
    
    -- Close button - simplified
    local closeButton = CreateFrame("Button", nil, buffConfigFrame)
    closeButton:SetSize(32, 32)
    closeButton:SetPoint("TOPRIGHT", -10, -10)
    closeButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeButton:SetScript("OnClick", function()
        buffConfigFrame:Hide()
    end)
    
    -- Create buff checkboxes
    local yOffset = -60
    local checkboxes = {}
    
    for spellId, buffName in pairs(availableBuffs) do
        -- Simple checkbox using basic textures
        local checkbox = CreateFrame("CheckButton", nil, buffConfigFrame)
        checkbox:SetPoint("TOPLEFT", 20, yOffset)
        checkbox:SetSize(24, 24)
        
        -- Checkbox textures
        local normal = checkbox:CreateTexture(nil, "ARTWORK")
        normal:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        normal:SetAllPoints()
        checkbox:SetNormalTexture(normal)
        
        local checked = checkbox:CreateTexture(nil, "ARTWORK")
        checked:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checked:SetAllPoints()
        checkbox:SetCheckedTexture(checked)
        
        -- Set initial state
        if PotionTrackerDB and PotionTrackerDB.trackedBuffs and PotionTrackerDB.trackedBuffs[spellId] then
            checkbox:SetChecked(PotionTrackerDB.trackedBuffs[spellId])
        else
            checkbox:SetChecked(false)
        end
        
        -- Buff name label
        local label = buffConfigFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", checkbox, "RIGHT", 10, 0)
        label:SetText(buffName)
        label:SetTextColor(1, 1, 1, 1) -- White text
        
        -- Store reference
        checkboxes[spellId] = checkbox
        
        yOffset = yOffset - 35
    end
    
    -- Store checkboxes for later use
    buffConfigFrame.checkboxes = checkboxes
    
    -- Save button - simplified
    local saveButton = CreateFrame("Button", nil, buffConfigFrame)
    saveButton:SetSize(100, 30)
    saveButton:SetPoint("BOTTOMLEFT", 20, 20)
    saveButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    saveButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    
    local saveText = saveButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    saveText:SetPoint("CENTER")
    saveText:SetText("Save")
    saveText:SetTextColor(1, 1, 1, 1)
    
    saveButton:SetScript("OnClick", function()
        -- Save checkbox states
        if not PotionTrackerDB.trackedBuffs then
            PotionTrackerDB.trackedBuffs = {}
        end
        
        for spellId, checkbox in pairs(checkboxes) do
            PotionTrackerDB.trackedBuffs[spellId] = checkbox:GetChecked()
        end
        
        -- Reload tracked buffs
        LoadTrackedBuffs()
        
        Print("Buff configuration saved!")
        buffConfigFrame:Hide()
    end)
    
    -- Reset button - simplified
    local resetButton = CreateFrame("Button", nil, buffConfigFrame)
    resetButton:SetSize(100, 30)
    resetButton:SetPoint("BOTTOMRIGHT", -20, 20)
    resetButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    resetButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    
    local resetText = resetButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    resetText:SetPoint("CENTER")
    resetText:SetText("Reset")
    resetText:SetTextColor(1, 1, 1, 1)
    
    resetButton:SetScript("OnClick", function()
        -- Reset to defaults
        for spellId, checkbox in pairs(checkboxes) do
            local defaultValue = (spellId == 11359 or spellId == 6615 or spellId == 17543 or 
                                 spellId == 17549 or spellId == 17548) -- Default enabled buffs
            checkbox:SetChecked(defaultValue)
        end
    end)
    
    -- Show the frame immediately
    buffConfigFrame:Show()
    
    Print("Buff config frame creation completed!")
    Print("Frame should now be visible with dark background and white text")
    return buffConfigFrame
end

-- Function to show buff configuration frame (made global for dropdown access)
ShowBuffConfigFrame = function()
    Print("ShowBuffConfigFrame called!")
    
    if not buffConfigFrame then
        Print("Creating buff config frame...")
        CreateBuffConfigFrame()
    end
    
    if not buffConfigFrame then
        Print("ERROR: Failed to create buff config frame!")
        return
    end
    
    Print("Buff config frame exists, showing...")
    
    -- Update checkbox states from current settings
    if PotionTrackerDB and PotionTrackerDB.trackedBuffs and buffConfigFrame.checkboxes then
        for spellId, checkbox in pairs(buffConfigFrame.checkboxes) do
            checkbox:SetChecked(PotionTrackerDB.trackedBuffs[spellId] or false)
        end
    end
    
    -- Show the frame
    buffConfigFrame:Show()
    
    Print("Buff config frame should now be visible!")
    Print("Frame exists: " .. tostring(buffConfigFrame ~= nil))
    Print("Frame is shown: " .. tostring(buffConfigFrame:IsShown()))
    Print("Frame is visible: " .. tostring(buffConfigFrame:IsVisible()))
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
}

-- Throttle for buff updates (prevent spam)
local lastUpdate = 0
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
        Print("Unit does not exist: " .. tostring(unit))
        return 
    end
    
    local unitName = UnitName(unit)
    if not unitName then 
        Print("Could not get unit name for: " .. tostring(unit))
        return 
    end

    Print("Checking buffs for " .. unitName)
    
    -- Check each tracked buff directly
    for spellId, buffName in pairs(trackedBuffs) do
        local auraName = GetSpellInfo(spellId) or buffName
        Print("Checking for buff: " .. tostring(auraName))
        local name, _, _, _, duration = AuraUtil.FindAuraByName(auraName, unit, "HELPFUL")
        if name then
            Print("Found tracked buff at load: " .. name)
            
            -- Print to chat
            local timeStr = ""
            if duration and duration > 0 then
                local minutes = math.floor(duration / 60)
                local seconds = duration % 60
                timeStr = string.format(" (%dm %ds)", minutes, seconds)
            end
            Print(unitName .. " has " .. name .. timeStr)
            
            -- Record the event immediately
            Print("About to record buff event")
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
            Print("Adding buff to history directly")
            table.insert(buffHistory, entry)
            if not PotionTrackerDB then PotionTrackerDB = {} end
            PotionTrackerDB.buffHistory = buffHistory
            Print("History size after adding: " .. #buffHistory)
        end
    end
    
    -- Store current state for future comparisons
    previousBuffs[unit] = GetUnitBuffs(unit)
end

-- Function to add event to history
local function AddToHistory(event)
    if not buffHistory then buffHistory = {} end
    Print("Adding to history: " .. (event.event or "unknown") .. " - " .. (event.buff or event.targetName or "unknown"))
    table.insert(buffHistory, event)
    -- Ensure we save to PotionTrackerDB
    if not PotionTrackerDB then PotionTrackerDB = {} end
    PotionTrackerDB.buffHistory = buffHistory
    Print("Current history size: " .. #buffHistory)
end

-- Function to record buff event
local function RecordBuffEvent(unitName, buffName, eventType, duration)
    Print("Recording buff event: " .. eventType .. " - " .. buffName)
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
    if currentTime - lastUpdate < UPDATE_THROTTLE then return end
    lastUpdate = currentTime
    
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
local function UpdateIconState()
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
    Print("Initializing buff tracking...")
    
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
local combatTarget = nil  -- Store the target we started combat with

-- Function to get target info
local function GetTargetInfo()
    if not UnitExists("target") then return nil end
    
    local name = UnitName("target")
    -- Only return info if it's a tracked mob
    if not trackedMobs[name] then return nil end
    
    local level = UnitLevel("target")
    local classification = UnitClassification("target")
    local isElite = classification == "elite" or classification == "rareelite"
    
    return {
        name = name,
        level = level,
        classification = classification,
        isElite = isElite
    }
end

-- Function to record combat event
local function RecordCombatEvent(eventType, target)
    if not target or not trackedMobs[target.name] then return end
    
    local eventInfo = {
        timestamp = time(),
        event = eventType,
        targetName = target.name,
        targetLevel = target.level,
        targetClassification = target.classification,
        duration = eventType == "COMBAT_END" and (time() - (combatStartTime or time())) or nil
    }
    
    -- Add to history
    AddToHistory(eventInfo)
    
    -- Print combat info
    if eventType == "COMBAT_START" then
        Print(string.format("Entered combat with %s (Level %d%s)", 
            target.name, 
            target.level,
            target.isElite and " Elite" or ""))
    elseif eventType == "COMBAT_END" then
        Print(string.format("Left combat with %s (Duration: %d seconds)", 
            target.name,
            eventInfo.duration))
    end
end

-- Event handler
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Initialize saved variables
        PotionTrackerDB = PotionTrackerDB or {
            minimapPos = 45,
            isTracking = false,
            buffHistory = {},
            exportedCSV = nil,
            trackedBuffs = {
                -- Default tracked buffs
                [11359] = true,  -- Greater Restoration
                [6615] = true,   -- Free Action
                [17543] = true,  -- Greater Fire Protection
                [17549] = true,  -- Greater Arcane Protection
                [17548] = true,  -- Greater Shadow Protection
                [17544] = false, -- Greater Nature Protection
                [17545] = false, -- Greater Frost Protection
            }
        }
        
        -- Load saved buff history
        buffHistory = PotionTrackerDB.buffHistory or {}
        
        -- Load tracked buffs from saved variables
        LoadTrackedBuffs()
        
        -- Create minimap icon
        minimapIcon = CreateMinimapIcon()
        
        -- Set initial tracking state
        isTracking = PotionTrackerDB.isTracking
        UpdateIconState()
        
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
                Print("New member joined: " .. name)
                InitializeUnitBuffs(unit)
            end
        end
        
        -- Update current group state
        currentGroupMembers = newGroupMembers
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat
        if not isTracking then return end
        
        -- Get target info when entering combat
        local target = GetTargetInfo()
        if target then
            combatStartTime = time()
            combatTarget = target  -- Store the target we started combat with
            RecordCombatEvent("COMBAT_START", target)
        end
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat
        if not isTracking or not combatStartTime then return end
        
        -- Use the stored combat target for the end event
        if combatTarget then
            RecordCombatEvent("COMBAT_END", combatTarget)
        end
        combatStartTime = nil
        currentTarget = nil
        combatTarget = nil  -- Clear the stored combat target
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Update current target info
        if isTracking then
            currentTarget = GetTargetInfo()
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
    end
end)

-- Slash command
SLASH_POTIONTRACKER1 = "/pt"
SlashCmdList["POTIONTRACKER"] = function(msg)
    if msg == "toggle" then
        ToggleTracking()
    elseif msg == "config" or msg == "buffs" then
        Print("Slash command: config")
        ShowBuffConfigFrame()
    elseif msg == "export" then
        ExportCSV()
        Print("Export complete. Logout to persist immediately if desired.")
    elseif msg == "clear" then
        -- Clear both in-memory and saved data
        PotionTrackerDB.buffHistory = {}
        buffHistory = {}
        PotionTrackerDB.exportedCSV = nil
        Print("History cleared. Fresh data will be saved going forward.")
    elseif msg == "stats" then
        local count = #(PotionTrackerDB.buffHistory or {})
        Print(string.format("Tracking %d buff events", count))
        
        -- Debug information
        Print("=== DEBUG INFO ===")
        Print("isTracking: " .. tostring(isTracking))
        Print("trackedBuffs count: " .. tostring(GetTableSize(trackedBuffs)))
        Print("Available buffs:")
        for spellId, buffName in pairs(availableBuffs) do
            local isTracked = trackedBuffs[spellId] ~= nil
            local isEnabled = PotionTrackerDB and PotionTrackerDB.trackedBuffs and PotionTrackerDB.trackedBuffs[spellId]
            Print(string.format("  %s (ID: %d) - Tracked: %s, Enabled: %s", 
                buffName, spellId, tostring(isTracked), tostring(isEnabled)))
        end
    elseif msg == "hidetest" then
        if _G.PotionTrackerTestFrame then
            _G.PotionTrackerTestFrame:Hide()
            Print("Test frame hidden")
        end
    elseif msg == "reload" then
        LoadTrackedBuffs()
        Print("Reloaded tracked buffs")
    else
        Print("Commands:")
        Print("/pt toggle - Toggle buff tracking")
        Print("/pt config - Configure tracked buffs")
        Print("/pt export - Export buff history (saves on logout)")
        Print("/pt clear - Clear buff history without reloading")
        Print("/pt stats - Show tracking statistics")
        Print("/pt reload - Reload tracked buffs")
        Print("/pt hidetest - Hide test frame")
    end
end
