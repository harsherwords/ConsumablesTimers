local _, addon = ...

local window, scroll, list, emptyText, input, feedback
local activeHeading, activeEmptyText
local inputCategory
local pendingCategories = {}
local rows = {}
local rowHeight = 28

local function CreateCategoryDropdown(parent, onChange)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetSize(128, 24)
    dropdown.categoryID = "personal"
    dropdown:SetupMenu(function(owner, root)
        for _, category in ipairs(addon.categories) do
            root:CreateRadio(category.name, function(value) return owner.categoryID == value end, onChange, category.id)
        end
    end)
    return dropdown
end

local function RevealTrackedSpell(id)
    for index, trackedID in ipairs(addon.GetTrackedSpellIDs()) do
        if trackedID == id then
            local rowTop = (index - 1) * rowHeight
            local visibleTop = scroll:GetVerticalScroll()
            local visibleHeight = scroll:GetHeight()
            if rowTop < visibleTop then
                scroll:SetVerticalScroll(rowTop)
            elseif rowTop + rowHeight > visibleTop + visibleHeight then
                scroll:SetVerticalScroll(rowTop + rowHeight - visibleHeight)
            end
            return
        end
    end
end

local function CreateRow()
    local row = CreateFrame("Frame", nil, list)
    row:SetHeight(rowHeight)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetSize(22, 22)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.remove = addon.CreateOptionsButton(row, "X", 28)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.remove:SetScript("OnClick", function()
        local _, message = addon.SetTrackedSpell(row.spellID, false)
        feedback:SetText(message)
    end)

    row.add = CreateFrame("Button", nil, row)
    row.add:SetPoint("CENTER", row.remove, "CENTER")
    row.add:SetSize(24, 24)
    row.add:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    row.add:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row.add:SetScript("OnClick", function()
        local id = row.spellID
        local changed, message = addon.SetTrackedSpell(id, true, row.category.categoryID)
        if changed then
            pendingCategories[id] = nil
            RevealTrackedSpell(id)
        end
        feedback:SetText(message)
    end)

    row.category = CreateCategoryDropdown(row, function(category)
        if addon.IsCombat() then
            return
        end
        local id = row.spellID
        if addon.db.spells[id] then
            addon.SetSpellCategory(id, category)
        else
            pendingCategories[id] = category
            row.category.categoryID = category
        end
    end)
    row.category:SetPoint("RIGHT", row.remove, "LEFT", -10, 0)
    row.idText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.idText:SetPoint("RIGHT", row.category, "LEFT", -10, 0)
    row.idText:SetWidth(68)
    row.idText:SetJustifyH("RIGHT")

    row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.nameText:SetPoint("RIGHT", row.idText, "LEFT", -12, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)
    return row
end

local function ShowSpellRow(index, top, id, activeBuff)
    local row = rows[index] or CreateRow()
    rows[index] = row
    local category = activeBuff and pendingCategories[id] or addon.GetSpellCategory(id)
    if row.spellID ~= id then
        row.category:CloseMenu()
    end
    row.spellID = id
    if row.category.categoryID ~= category then
        row.category.categoryID = category
        row.category:GenerateMenu()
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -top)
    row:SetPoint("TOPRIGHT", 0, -top)

    local alpha = activeBuff and 0.55 or 1
    row.icon:SetTexture(activeBuff and activeBuff.icon or addon.GetSpellIcon(id))
    row.icon:SetAlpha(alpha)
    row.nameText:SetText(activeBuff and activeBuff.name or C_Spell.GetSpellName(id) or "Unknown spell")
    row.nameText:SetAlpha(alpha)
    row.idText:SetText(tostring(id))
    row.idText:SetAlpha(alpha)
    row.add:SetShown(activeBuff ~= nil)
    row.remove:SetShown(activeBuff == nil)
    row:Show()
end

function addon.RefreshTrackingWindow()
    if not window or not window:IsVisible() or addon.IsCombat() then
        return
    end
    local ids = addon.GetTrackedSpellIDs()
    emptyText:SetShown(#ids == 0)
    for index, id in ipairs(ids) do
        ShowSpellRow(index, (index - 1) * rowHeight, id)
    end

    local trackedHeight = math.max(1, #ids) * rowHeight
    activeHeading:ClearAllPoints()
    activeHeading:SetPoint("TOPLEFT", 4, -trackedHeight - 7)

    local activeBuffs = addon.ReadActiveBuffs(addon.db.spells)
    local activeCount = activeBuffs and #activeBuffs or 0
    local activeTop = trackedHeight + 28
    activeEmptyText:SetShown(activeCount == 0)
    if activeCount == 0 then
        activeEmptyText:SetText(activeBuffs and "No active buffs to add" or "Active buffs unavailable")
    end
    for index, buff in ipairs(activeBuffs or {}) do
        ShowSpellRow(#ids + index, activeTop + (index - 1) * rowHeight, buff.id, buff)
    end
    for index = #ids + activeCount + 1, #rows do
        rows[index].category:CloseMenu()
        rows[index]:Hide()
    end

    local height = activeTop + math.max(1, activeCount) * rowHeight
    list:SetHeight(height)
    local maxScroll = math.max(0, height - scroll:GetHeight())
    if scroll:GetVerticalScroll() > maxScroll then
        scroll:SetVerticalScroll(maxScroll)
    end
end

local function TrackInput()
    local id = addon.ParseSpellID(input:GetText())
    local changed, message = addon.SetTrackedSpell(id, true, inputCategory.categoryID)
    if changed then
        input:SetText("")
        input:ClearFocus()
    end
    feedback:SetText(message)
end

local function CreateTrackingWindow()
    local windowWidth = 600
    window = addon.CreateOptionsWindow("ConsumablesTimersTracking", "Tracked Spells", windowWidth, 335)

    local config = addon.CreateOptionsButton(window, "Config", 82)
    config:SetPoint("TOPRIGHT", -40, -10)
    config:SetScript("OnClick", addon.OpenOptions)

    local label = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 16, -53)
    label:SetText("Spell ID")

    input = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", 87, -47)
    input:SetHeight(24)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", TrackInput)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    local track = addon.CreateOptionsButton(window, "Track", 80)
    track:SetPoint("TOPRIGHT", -30, -47)
    track:SetScript("OnClick", TrackInput)
    inputCategory = CreateCategoryDropdown(window, function(category)
        if not addon.IsCombat() then
            inputCategory.categoryID = category
        end
    end)
    inputCategory:SetPoint("TOPRIGHT", track, "TOPLEFT", -10, 0)
    input:SetPoint("TOPRIGHT", inputCategory, "TOPLEFT", -12, 0)

    scroll = CreateFrame("ScrollFrame", "ConsumablesTimersTrackingScroll", window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -88)
    scroll:SetPoint("BOTTOMRIGHT", -30, 37)
    list = CreateFrame("Frame", nil, scroll)
    list:SetSize(windowWidth - 46, rowHeight)
    scroll:SetScrollChild(list)

    emptyText = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 4, -6)
    emptyText:SetText("None added")

    activeHeading = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    activeHeading:SetText("Active buffs")
    activeEmptyText = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    activeEmptyText:SetPoint("TOPLEFT", activeHeading, "BOTTOMLEFT", 0, -8)

    feedback = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    feedback:SetPoint("BOTTOMLEFT", 16, 14)
    feedback:SetPoint("BOTTOMRIGHT", -16, 14)
    feedback:SetJustifyH("LEFT")

    window:SetScript("OnEvent", addon.RefreshTrackingWindow)
    window:SetScript("OnShow", function(self)
        self:RegisterUnitEvent("UNIT_AURA", "player")
        addon.RefreshTrackingWindow()
    end)
    window:SetScript("OnHide", function(self)
        self:UnregisterEvent("UNIT_AURA")
        inputCategory:CloseMenu()
        for _, row in ipairs(rows) do
            row.category:CloseMenu()
        end
        pendingCategories = {}
        input:ClearFocus()
    end)
end

function addon.OpenTrackingWindow()
    if addon.IsCombat() then
        return
    end
    addon.CloseOptions()
    if not window then
        CreateTrackingWindow()
    end
    if not window:IsShown() then
        input:SetText("")
        feedback:SetText("")
        window:Show()
        scroll:SetVerticalScroll(0)
    end
end

function addon.CloseTrackingWindow()
    if window then
        window:Hide()
    end
end
