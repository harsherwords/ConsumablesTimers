local _, addon = ...

local window, scroll, list, emptyText, input, feedback
local rows = {}
local rowHeight = 28

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, list)
    local y = -(index - 1) * rowHeight
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(rowHeight)

    row.idText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.idText:SetPoint("LEFT", 4, 0)

    row.remove = addon.CreateOptionsButton(row, "X", 28)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.remove:SetScript("OnClick", function(self)
        local _, message = addon.SetTrackedSpell(self.spellID, false)
        feedback:SetText(message)
    end)
    return row
end

function addon.RefreshTrackingWindow()
    if not window or not window:IsShown() then
        return
    end
    local ids = addon.GetTrackedSpellIDs()
    emptyText:SetShown(#ids == 0)
    for index, id in ipairs(ids) do
        local row = rows[index] or CreateRow(index)
        rows[index] = row
        row.idText:SetText(tostring(id))
        row.remove.spellID = id
        row:Show()
    end
    for index = #ids + 1, #rows do
        rows[index]:Hide()
    end

    local height = math.max(1, #ids) * rowHeight
    list:SetHeight(height)
    local maxScroll = math.max(0, height - scroll:GetHeight())
    if scroll:GetVerticalScroll() > maxScroll then
        scroll:SetVerticalScroll(maxScroll)
    end
end

local function TrackInput()
    local id = addon.ParseSpellID(input:GetText())
    local changed, message = addon.SetTrackedSpell(id, true)
    if changed then
        input:SetText("")
        input:ClearFocus()
    end
    feedback:SetText(message)
end

local function CreateTrackingWindow()
    window = addon.CreateOptionsWindow("ConsumablesTimersTracking", "Tracked Spell IDs", 350, 335)

    local label = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 16, -53)
    label:SetText("Spell ID")

    input = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", 87, -47)
    input:SetSize(151, 24)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", TrackInput)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    local track = addon.CreateOptionsButton(window, "Track", 80)
    track:SetPoint("LEFT", input, "RIGHT", 10, 0)
    track:SetScript("OnClick", TrackInput)

    scroll = CreateFrame("ScrollFrame", "ConsumablesTimersTrackingScroll", window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -88)
    scroll:SetPoint("BOTTOMRIGHT", -30, 37)
    list = CreateFrame("Frame", nil, scroll)
    list:SetSize(304, rowHeight)
    scroll:SetScrollChild(list)

    emptyText = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 4, -6)
    emptyText:SetText("None added")

    feedback = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    feedback:SetPoint("BOTTOMLEFT", 16, 14)
    feedback:SetPoint("BOTTOMRIGHT", -16, 14)
    feedback:SetJustifyH("LEFT")

    window:SetScript("OnHide", function()
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
        addon.RefreshTrackingWindow()
        scroll:SetVerticalScroll(0)
    end
end

function addon.CloseTrackingWindow()
    if window then
        window:Hide()
    end
end
