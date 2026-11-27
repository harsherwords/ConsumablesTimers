local _, addon = ...

addon.fonts = {
    { name = "Default", path = STANDARD_TEXT_FONT },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

function addon.HexToRGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end

local function ApplyFont(text, style)
    local flags = style.outline and "OUTLINE" or ""
    if not text:SetFont(addon.fonts[style.font].path, style.size, flags) then
        text:SetFont(STANDARD_TEXT_FONT, style.size, flags)
    end
    text:SetTextColor(addon.HexToRGB(style.color))
end

local function MoveToSavedPosition(frame, position)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
end

local function MakeMovable(frame, positionKey)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if addon.IsCombat() or addon.db.locked then
            return
        end
        self.moving = true
        self:StartMoving()
    end)
    local function FinishMoving(self)
        if not self.moving then
            return
        end
        self.moving = nil
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if x and parentX then
            local position = addon.db[positionKey]
            position.x, position.y = x - parentX, y - parentY
            MoveToSavedPosition(self, position)
        end
    end
    frame.FinishMoving = FinishMoving
    frame:SetScript("OnDragStop", FinishMoving)
    frame:SetScript("OnHide", FinishMoving)
end

local panel, warning, title, warningText, lockButton
local rows = {}
local headings = {}

local function ShowLockTooltip(button)
    if addon.IsCombat() then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(addon.db.locked and "Unlock timer and warning" or "Lock timer and warning")
    GameTooltip:Show()
end

local function HideLockTooltip(button)
    if GameTooltip:IsOwned(button) then
        GameTooltip:Hide()
    end
end

function addon.CreateDisplay()
    panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetFrameStrata("MEDIUM")
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.05, 0.06, 0.08, 0.88)
    panel:SetBackdropBorderColor(0.35, 0.37, 0.43, 0.9)
    MakeMovable(panel, "timerPosition")
    panel:Hide()

    title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 9, -6)
    title:SetPoint("TOPRIGHT", -30, -6)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    warning = CreateFrame("Frame", nil, UIParent)
    warning:SetFrameStrata("HIGH")
    warningText = warning:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    warningText:SetPoint("TOPLEFT", 6, -5)
    warningText:SetPoint("TOPRIGHT", -6, -5)
    warningText:SetJustifyH("CENTER")
    MakeMovable(warning, "warningPosition")
    warning:Hide()

    lockButton = CreateFrame("Button", nil, panel)
    lockButton:SetPoint("TOPRIGHT", -4, -3)
    lockButton:SetSize(21, 21)
    lockButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    lockButton:SetScript("OnClick", function()
        addon.SetLocked(not addon.db.locked)
    end)
    lockButton:SetScript("OnEnter", ShowLockTooltip)
    lockButton:SetScript("OnLeave", HideLockTooltip)
    lockButton:SetScript("OnHide", HideLockTooltip)

    addon.RestorePositions()
end

function addon.RestorePositions()
    MoveToSavedPosition(panel, addon.db.timerPosition)
    MoveToSavedPosition(warning, addon.db.warningPosition)
end

function addon.UpdateInteraction()
    local combat = addon.IsCombat()
    local locked = addon.db.locked
    local interactive = not locked and not combat
    for _, frame in ipairs({ panel, warning }) do
        if not interactive then
            frame:FinishMoving()
        end
        frame:EnableMouse(interactive)
    end
    lockButton:SetNormalTexture(locked and "Interface\\Buttons\\LockButton-Locked-Up"
        or "Interface\\Buttons\\LockButton-Unlocked-Up")
    lockButton:EnableMouse(not combat)
    lockButton:SetShown(not combat)
    if not combat and GameTooltip:IsOwned(lockButton) then
        ShowLockTooltip(lockButton)
    end
end

local function CreateRow()
    local row = CreateFrame("Frame", nil, panel)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT")
    row.icon:SetSize(23, 23)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.timer = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.timer:SetPoint("RIGHT")
    row.timer:SetJustifyH("RIGHT")
    row.timer:SetWordWrap(false)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -1)
    row.count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    row.count:Hide()
    return row
end

function addon.LayoutDisplay(entries)
    local db = addon.db
    local styles = db.styles
    ApplyFont(title, styles.title)
    ApplyFont(warningText, styles.warning)
    title:SetText(db.text.title)
    title:SetShown(db.text.title ~= "")

    local top = math.max(25, title:IsShown() and styles.title.size + 11 or 0)
    local height = math.max(27, styles.timer.size + 6, db.showLabels and styles.label.size + 6 or 0)
    local labelWidth, timerWidth = 0, 76
    local text = db.text
    local timerSamples = { "88:88:88", text.missing, text.active, text.unavailable, text.inCombat }
    local headingCount, headingWidth, currentCategory = 0, 0, nil
    for index, entry in ipairs(entries) do
        if entry.category ~= currentCategory then
            currentCategory = entry.category
            local category = addon.GetCategoryName(currentCategory)
            if index > 1 or category ~= text.title then
                headingCount = headingCount + 1
                local heading = headings[headingCount] or panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                headings[headingCount] = heading
                ApplyFont(heading, styles.title)
                heading:ClearAllPoints()
                heading:SetPoint("TOPLEFT", 9, -top - 3)
                heading:SetText(category)
                heading:Show()
                headingWidth = math.max(headingWidth, heading:GetUnboundedStringWidth() + 18)
                top = top + styles.title.size + 9
            end
        end
        local row = rows[index] or CreateRow()
        rows[index] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -top)
        row:SetPoint("TOPRIGHT", -9, -top)
        row:SetHeight(height)
        top = top + height
        ApplyFont(row.label, styles.label)
        ApplyFont(row.timer, styles.timer)
        row.label:SetText(entry.label)
        row.label:SetShown(db.showLabels)
        if db.showLabels then
            labelWidth = math.max(labelWidth, row.label:GetUnboundedStringWidth() + 10)
        end
        for _, sample in ipairs(timerSamples) do
            row.timer:SetText(sample)
            timerWidth = math.max(timerWidth, row.timer:GetUnboundedStringWidth() + 2)
        end
        row:Show()
    end
    for index = #entries + 1, #rows do
        rows[index]:Hide()
    end
    for index = headingCount + 1, #headings do
        headings[index]:Hide()
    end

    labelWidth, timerWidth = math.min(labelWidth, 240), math.min(timerWidth, 280)
    local width = math.max(134, title:GetUnboundedStringWidth() + 39, headingWidth, 47 + labelWidth + timerWidth)
    panel:SetSize(math.min(width, 570), top + 5)
    for index = 1, #entries do
        local row = rows[index]
        row.label:SetWidth(math.max(1, labelWidth - 10))
        row.timer:SetWidth(timerWidth)
    end
    warning:SetWidth(math.min(660, UIParent:GetWidth() - 16))
end

local function FormatTime(seconds)
    seconds = math.ceil(seconds)
    local minutes = math.floor(seconds / 60)
    if minutes >= 60 then
        return string.format("%d:%02d:%02d", math.floor(minutes / 60), minutes % 60, seconds % 60)
    end
    return string.format("%d:%02d", minutes, seconds % 60)
end

function addon.Render(entries, timers, combat, showWarning, previewWarning)
    local db = addon.db
    local text = db.text
    local unavailableText = combat and text.inCombat or text.unavailable
    local timerR, timerG, timerB = addon.HexToRGB(db.styles.timer.color)
    local missingR, missingG, missingB = addon.HexToRGB(db.missingColor)
    local missing = {}
    local previewLabel
    for index, entry in ipairs(entries) do
        local row, result = rows[index], timers[entry.key]
        local status, icon, alpha = text.missing, entry.icon, 0.45
        local itemID = entry.click and entry.click.itemID
        row.itemCount = itemID and addon.GetBagCount(itemID) or 0
        if previewWarning and not previewLabel and not entry.useOnly then
            previewLabel = entry.label
        end
        if entry.useOnly then
            status = "x" .. row.itemCount
        elseif result == addon.unavailable then
            status, alpha = unavailableText, 0.65
        elseif result then
            status = result.remaining == math.huge and text.active or FormatTime(result.remaining)
            icon, alpha = result.icon or icon, 1
        elseif showWarning then
            missing[#missing + 1] = entry.label
        end
        if itemID then
            icon = entry.click.icon or icon
            alpha = row.itemCount > 0 and 1 or 0.45
        end
        local countShown = itemID ~= nil and not entry.useOnly
        row.count:SetShown(countShown)
        if countShown then
            local count = row.itemCount
            row.count:SetText(tostring(count))
            if count <= 1 then
                row.count:SetTextColor(1, 0.32, 0.32)
            elseif count <= 20 then
                row.count:SetTextColor(1, 0.86, 0.24)
            else
                row.count:SetTextColor(0.35, 1, 0.43)
            end
        end
        addon.UpdateRowClick(row, entry.click, not combat and db.locked and (not itemID or row.itemCount > 0))
        row.icon:SetTexture(icon)
        row.icon:SetAlpha(alpha)
        row.timer:SetText(status)
        if result or entry.useOnly then
            row.timer:SetTextColor(timerR, timerG, timerB)
        else
            row.timer:SetTextColor(missingR, missingG, missingB)
        end
    end

    panel:Show()
    if showWarning and (#missing > 0 or previewLabel) then
        local names = #missing > 0 and table.concat(missing, ", ") or previewLabel
        local message = text.warning:gsub("%%s", function() return names end)
        warningText:SetText(message)
        warning:SetHeight(math.max(20, warningText:GetStringHeight() + 10))
        warning:SetFrameStrata(previewWarning and "FULLSCREEN_DIALOG" or "HIGH")
        warning:SetShown(message ~= "")
    else
        warning:Hide()
    end
end

function addon.HideDisplay()
    panel:Hide()
    warning:Hide()
end
