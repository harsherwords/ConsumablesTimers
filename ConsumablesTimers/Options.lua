local _, addon = ...

local panel, content, status
local checks, textInputs, styleInputs = {}, {}, {}
local missingColorInput, pickerCallback
local missingColorSwatches = {}
local clickOptions
local specSections = {}

local function ParseHexColor(text)
    return strtrim(text):upper():match("^#?(%x%x%x%x%x%x)$")
end

local function Label(text, x, y, template)
    local label = content:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, -y)
    label:SetText(text)
    return label
end

local function Checkbox(parent, text, x, y)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetPoint("TOPLEFT", x, -y)
    check:SetSize(24, 24)
    check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 3, 0)
    label:SetText(text)
    check:SetHitRectInsets(0, -label:GetStringWidth() - 3, 0, 0)
    return check
end

local function EditBox(x, y, width, maxLetters)
    local edit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    edit:SetPoint("TOPLEFT", x, -y)
    edit:SetSize(width, 24)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(maxLetters)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEnterPressed", edit.ClearFocus)
    return edit
end

function addon.CreateOptionsButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(text)
    return button
end

local function CloseMissingColorPicker()
    if pickerCallback and ColorPickerFrame.swatchFunc == pickerCallback then
        ColorPickerFrame:Hide()
    end
    pickerCallback = nil
end

local function OpenMissingColorPicker()
    if addon.IsCombat() then
        return
    end
    local picker = ColorPickerFrame
    local previous = missingColorInput:GetText()
    local r, g, b = addon.HexToRGB(ParseHexColor(previous) or addon.db.missingColor)
    local function UpdatePickerColor()
        if addon.OptionsShown() and not addon.IsCombat() then
            local red, green, blue = picker:GetColorRGB()
            missingColorInput:SetText(string.format("#%02X%02X%02X", math.floor(red * 255 + 0.5),
                math.floor(green * 255 + 0.5), math.floor(blue * 255 + 0.5)))
        end
    end
    pickerCallback = UpdatePickerColor
    picker:SetupColorPickerAndShow({
        r = r, g = g, b = b,
        swatchFunc = UpdatePickerColor,
        cancelFunc = function()
            if addon.OptionsShown() and not addon.IsCombat() then
                missingColorInput:SetText(previous)
            end
        end,
    })
end

local function AddMissingColorOptions(y)
    Label("Missing text color", 12, y + 6)
    local presets = { "FF5E5E", "FFA256", "FFDB72", "79DB95", "77BDFF", "FFFFFF" }
    for index, hex in ipairs(presets) do
        local swatch = CreateFrame("Button", nil, content)
        swatch:SetPoint("TOPLEFT", 140 + (index - 1) * 24, -y - 2)
        swatch:SetSize(20, 20)
        local border = swatch:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        local color = swatch:CreateTexture(nil, "ARTWORK")
        color:SetPoint("TOPLEFT", 2, -2)
        color:SetPoint("BOTTOMRIGHT", -2, 2)
        color:SetColorTexture(addon.HexToRGB(hex))
        swatch:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        swatch:SetScript("OnClick", function()
            if not addon.IsCombat() then
                missingColorInput:SetText("#" .. hex)
            end
        end)
        missingColorSwatches[hex] = border
    end

    local pickerButton = addon.CreateOptionsButton(content, "Color picker", 87)
    pickerButton:SetPoint("TOPLEFT", 289, -y)
    pickerButton:SetScript("OnClick", OpenMissingColorPicker)
    missingColorInput = EditBox(384, y, 68, 7)
    missingColorInput:SetScript("OnTextChanged", function(self)
        local selected = ParseHexColor(self:GetText())
        for hex, border in pairs(missingColorSwatches) do
            local shade = hex == selected and 0.95 or 0.23
            border:SetColorTexture(shade, shade, shade)
        end
    end)
end

function addon.OptionsShown()
    return panel and panel:IsShown()
end

function addon.CloseOptions()
    if panel then
        panel:Hide()
    end
end

local function LoadOptions()
    local db = addon.db
    for key, check in pairs(checks) do
        check:SetChecked(db[key])
    end
    for key, edit in pairs(textInputs) do
        edit:SetText(db.text[key])
    end
    missingColorInput:SetText("#" .. db.missingColor:upper())
    for key, inputs in pairs(styleInputs) do
        local style = db.styles[key]
        inputs.fontIndex = style.font
        inputs.font:SetText(addon.fonts[style.font].name)
        inputs.size:SetText(tostring(style.size))
        inputs.color:SetText(style.color)
        inputs.outline:SetChecked(style.outline)
    end
    status:SetText("")
end

local function ApplyText()
    if addon.IsCombat() then
        return
    end
    local missingColor = ParseHexColor(missingColorInput:GetText())
    if not missingColor then
        status:SetText("Enter a six-digit hex color for missing buffs.")
        return
    end
    local styles = {}
    for key, inputs in pairs(styleInputs) do
        local size = tonumber(inputs.size:GetText())
        local color = ParseHexColor(inputs.color:GetText())
        if not size or size % 1 ~= 0 or size < 8 or size > 48 or not color then
            status:SetText("Use a whole font size from 8 to 48 and a six-digit hex color.")
            return
        end
        styles[key] = { font = inputs.fontIndex, size = size, color = color,
            outline = inputs.outline:GetChecked() and true or false }
    end

    CloseMissingColorPicker()
    local db = addon.db
    for key, edit in pairs(textInputs) do
        db.text[key] = strtrim(edit:GetText())
        edit:ClearFocus()
    end
    db.missingColor = missingColor
    missingColorInput:ClearFocus()
    db.styles = styles
    addon.RebuildDisplay()
    LoadOptions()
    status:SetText("Text settings applied.")
end

local function AddBehaviorOptions()
    Label("Behavior", 10, 10, "GameFontNormal")
    local settings = {
        { "outOfCombatOnly", "Show timers only outside combat" },
        { "warn", "Show large missing-buff warnings outside combat" },
        { "disableWorld", "Disable in the world" },
        { "disableDungeon", "Disable in dungeons" },
        { "disableRaid", "Disable in raids" },
        { "locked", "Lock timer and warning positions" },
        { "showLabels", "Show buff names beside the icons" },
        { "hideDefaultBuffs", "Hide the default Well Fed and Weapon Oil trackers" },
    }
    for index, setting in ipairs(settings) do
        local key, name = unpack(setting)
        local check = Checkbox(content, name, 10, 28 + (index - 1) * 25)
        checks[key] = check
        check:SetScript("OnClick", function(self)
            if addon.IsCombat() then
                self:SetChecked(addon.db[key])
                return
            end
            local checked = self:GetChecked() and true or false
            if key == "locked" then
                addon.SetLocked(checked)
            else
                addon.db[key] = checked
                addon.RebuildDisplay()
            end
        end)
    end
end

local function AddTextOptions()
    local offset = 25
    Label("Display text", 10, 220 + offset, "GameFontNormal")
    local fields = {
        { "title", "Window title" }, { "wellfed", "Food label" }, { "weapon", "Weapon label" },
        { "missing", "Missing timer" }, { "active", "Timer with no expiry" },
        { "unavailable", "Unavailable timer" }, { "inCombat", "Unavailable in combat" },
        { "warning", "Warning message (%s = buff names)" },
        { "flask", "Flask label" },
    }
    for index, field in ipairs(fields) do
        local key, name = unpack(field)
        local y = 244 + offset + (index - 1) * 30 + (index > 4 and 34 or 0)
        Label(name, 12, y + 6)
        textInputs[key] = EditBox(230, y, 222, key == "warning" and 180 or 80)
    end
    AddMissingColorOptions(364 + offset)

    offset = offset + 30
    Label("Text appearance", 10, 529 + offset, "GameFontNormal")
    Label("Font", 104, 555 + offset)
    Label("Size", 252, 555 + offset)
    Label("Hex color", 312, 555 + offset)
    local textStyles = { { "title", "Title" }, { "label", "Buff names" },
        { "timer", "Timers" }, { "warning", "Warning" } }
    for index, style in ipairs(textStyles) do
        local key, name = unpack(style)
        local y = 576 + offset + (index - 1) * 32
        Label(name, 12, y + 5)
        local inputs = {}
        inputs.font = addon.CreateOptionsButton(content, "", 126)
        inputs.font:SetPoint("TOPLEFT", 101, -y)
        inputs.font:SetScript("OnClick", function(self)
            if not addon.IsCombat() then
                inputs.fontIndex = inputs.fontIndex % #addon.fonts + 1
                self:SetText(addon.fonts[inputs.fontIndex].name)
            end
        end)
        inputs.size = EditBox(253, y, 43, 2)
        inputs.color = EditBox(312, y, 71, 7)
        inputs.outline = Checkbox(content, "Outline", 395, y - 2)
        styleInputs[key] = inputs
    end
    Label("Change added spell labels with /ct label <spellID> <text>.", 12, 717 + offset)
end

local function CreateConsumableDropdown(parent, spec, kind, caption, y)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 8, -y - 5)
    label:SetText(caption)

    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 78, -y)
    dropdown:SetSize(310, 24)
    dropdown:SetDefaultText("None")
    dropdown:SetupMenu(function(_, root)
        local selected = addon.GetItemChoice(spec, kind)
        local function IsSelected(choice)
            return addon.GetItemChoice(spec, kind) == choice
        end
        local function SelectItem(choice)
            addon.SetItemChoice(spec, kind, choice)
        end

        root:SetScrollMode(260)
        local id = addon.GetAutomaticItem(kind)
        local autoLabel = id and ("Auto - " .. addon.GetConsumableName(id)) or "Auto (highest required level)"
        root:CreateRadio(autoLabel, IsSelected, SelectItem, "auto")
        root:CreateRadio("None", IsSelected, SelectItem, "none")
        local listed = false
        local includeUses = kind == "weapon"
        for _, item in ipairs(addon.GetBagConsumables(kind)) do
            local details = item.requiredLevel and item.requiredLevel > 0 and ("Requires " .. item.requiredLevel .. ", ") or ""
            local count = addon.GetBagCount(item.id, includeUses)
            local unit = includeUses and (count == 1 and " use left" or " uses left") or " in bags"
            local itemLabel = item.name .. " (" .. details .. count .. unit .. ")"
            root:CreateRadio(itemLabel, IsSelected, SelectItem, item.id)
            listed = listed or selected == item.id
        end
        if type(selected) == "number" and not listed then
            root:CreateRadio(addon.GetConsumableName(selected) .. " (out of bags)", IsSelected, SelectItem, selected)
        end
    end)
    return dropdown
end

local function BuildClickOptions()
    clickOptions = CreateFrame("Frame", nil, panel)
    clickOptions:SetPoint("TOPLEFT", 20, -84)
    clickOptions:SetPoint("BOTTOMRIGHT", -20, 22)
    local instructions = clickOptions:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    instructions:SetPoint("TOPLEFT", 8, -4)
    instructions:SetPoint("TOPRIGHT", -8, -4)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("Auto picks items from your bags with the highest Required Level you meet. Lock the timer window to click items or cast known helpful spells on yourself outside combat.")

    for spec = 1, 2 do
        local section = CreateFrame("Frame", nil, clickOptions)
        section:SetPoint("TOPLEFT", 0, -60 - (spec - 1) * 142)
        section:SetSize(470, 130)
        section.header = section:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        section.header:SetPoint("TOPLEFT", 8, 0)
        section.food = CreateConsumableDropdown(section, spec, "food", "Food", 24)
        section.flask = CreateConsumableDropdown(section, spec, "flask", "Flask", 57)
        section.weapon = CreateConsumableDropdown(section, spec, "weapon", "Weapon", 90)
        specSections[spec] = section
    end
    clickOptions:SetScript("OnShow", addon.RefreshClickOptions)
    clickOptions:SetScript("OnHide", function()
        for _, section in ipairs(specSections) do
            section.food:CloseMenu()
            section.flask:CloseMenu()
            section.weapon:CloseMenu()
        end
    end)
    clickOptions:Hide()
end

function addon.RefreshClickOptions()
    if not clickOptions or not clickOptions:IsVisible() or addon.IsCombat() then
        return
    end
    local activeSpec = addon.GetActiveSpec()
    for spec, section in ipairs(specSections) do
        local visible = spec == 1 or addon.HasSecondarySpec()
        section:SetShown(visible)
        if visible then
            local title = spec == 1 and "Primary spec" or "Secondary spec"
            section.header:SetText(activeSpec == spec and title .. " (active)" or title)
            section.food:GenerateMenu()
            section.flask:GenerateMenu()
            section.weapon:GenerateMenu()
        end
    end
end

local function ClearTextFocus()
    CloseMissingColorPicker()
    missingColorInput:ClearFocus()
    for _, edit in pairs(textInputs) do
        edit:ClearFocus()
    end
    for _, inputs in pairs(styleInputs) do
        inputs.size:ClearFocus()
        inputs.color:ClearFocus()
    end
end

function addon.CreateOptionsWindow(name, caption, width, height)
    local window = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    window:SetPoint("CENTER")
    window:SetSize(width, height)
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    window:SetBackdropColor(0.07, 0.08, 0.1, 0.98)
    window:SetBackdropBorderColor(0.42, 0.44, 0.50, 1)
    window:Hide()
    table.insert(UISpecialFrames, name)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(caption)
    return window
end

function addon.OpenOptions()
    if addon.IsCombat() then
        return
    end
    addon.CloseTrackingWindow()
    if not panel then
        panel = addon.CreateOptionsWindow("ConsumablesTimersOptions", "ConsumablesTimers", 530, 545)

        local scroll = CreateFrame("ScrollFrame", "ConsumablesTimersOptionsScroll", panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 13, -74)
        scroll:SetPoint("BOTTOMRIGHT", -30, 51)
        content = CreateFrame("Frame", nil, scroll)
        content:SetSize(485, 800)
        scroll:SetScrollChild(content)
        AddBehaviorOptions()
        AddTextOptions()

        local apply = addon.CreateOptionsButton(panel, "Apply text settings", 140)
        apply:SetPoint("BOTTOMRIGHT", -13, 14)
        apply:SetScript("OnClick", ApplyText)
        status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        status:SetPoint("BOTTOMLEFT", 16, 22)
        status:SetPoint("RIGHT", apply, "LEFT", -10, 0)
        status:SetJustifyH("LEFT")

        BuildClickOptions()
        local generalTab = addon.CreateOptionsButton(panel, "General", 93)
        generalTab:SetPoint("TOPLEFT", 16, -43)
        local actionTab = addon.CreateOptionsButton(panel, "On-Click Settings", 144)
        actionTab:SetPoint("LEFT", generalTab, "RIGHT", 5, 0)
        local trackingTab = addon.CreateOptionsButton(panel, "Tracking", 93)
        trackingTab:SetPoint("LEFT", actionTab, "RIGHT", 5, 0)
        trackingTab:SetScript("OnClick", addon.OpenTrackingWindow)
        local function SelectTab(general)
            if addon.IsCombat() then
                return
            end
            ClearTextFocus()
            scroll:SetShown(general)
            apply:SetShown(general)
            status:SetShown(general)
            clickOptions:SetShown(not general)
            generalTab:SetEnabled(not general)
            actionTab:SetEnabled(general)
        end
        generalTab:SetScript("OnClick", function() SelectTab(true) end)
        actionTab:SetScript("OnClick", function() SelectTab(false) end)
        SelectTab(true)

        panel:SetScript("OnHide", function()
            ClearTextFocus()
            addon.Refresh()
        end)
    end
    if not panel:IsShown() then
        LoadOptions()
        panel:Show()
        addon.Refresh()
    end
end

function addon.SyncLockOption()
    if checks.locked then
        checks.locked:SetChecked(addon.db.locked)
    end
end
