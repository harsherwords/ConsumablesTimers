local name, addon = ...

addon.categories = {
    { id = "consumables", name = "Consumables" },
    { id = "group", name = "Party & Raid" },
    { id = "personal", name = "Personal" },
}
local categoryNames = {}
for _, category in ipairs(addon.categories) do
    categoryNames[category.id] = category.name
end

local defaults = {
    outOfCombatOnly = false,
    warn = false,
    disableWorld = false,
    disableDungeon = false,
    disableRaid = false,
    locked = true,
    showLabels = false,
    hideDefaultBuffs = false,
    missingColor = "FF5E5E",
    timerPosition = { x = -270, y = 125 },
    warningPosition = { x = 0, y = 190 },
    text = {
        title = "Consumables", wellfed = "Well Fed", weapon = "Weapon Oil", flask = "Flask",
        imbue = "Weapon Imbue",
        missing = "Missing", active = "Active", unavailable = "Unavailable", inCombat = "In Combat",
        warning = "Missing: %s",
    },
    styles = {
        title = { font = 1, size = 11, color = "F4D07A", outline = false },
        label = { font = 1, size = 12, color = "F1F1F1", outline = false },
        timer = { font = 1, size = 14, color = "FFFFFF", outline = true },
        warning = { font = 1, size = 28, color = "FF655A", outline = true },
    },
    spells = {},
    spellCategories = {},
}

local function ApplyDefaults(saved, source)
    if type(saved) ~= "table" then
        saved = {}
    end
    for key, value in pairs(source) do
        if type(value) == "table" then
            saved[key] = ApplyDefaults(saved[key], value)
        elseif type(saved[key]) ~= type(value) then
            saved[key] = value
        end
    end
    return saved
end

function addon.IsSpellID(id)
    return type(id) == "number" and id >= 1 and id <= 2147483647 and id % 1 == 0
end

function addon.ParseSpellID(text)
    local id = tonumber(strtrim(text):match("^%d+$"))
    if addon.IsSpellID(id) then
        return id
    end
end

local function LoadDatabase()
    local db = ApplyDefaults(ConsumablesTimersDB, defaults)
    if not db.missingColor:match("^%x%x%x%x%x%x$") then
        db.missingColor = defaults.missingColor
    end
    for key, style in pairs(db.styles) do
        if defaults.styles[key] then
            if style.font % 1 ~= 0 or not addon.fonts[style.font] then
                style.font = defaults.styles[key].font
            end
            if style.size % 1 ~= 0 or style.size < 8 or style.size > 48 then
                style.size = defaults.styles[key].size
            end
            if not style.color:match("^%x%x%x%x%x%x$") then
                style.color = defaults.styles[key].color
            end
        end
    end
    local spells = {}
    local categories = {}
    for key, label in pairs(db.spells) do
        local id = tonumber(key)
        if addon.IsSpellID(id) and type(label) == "string" then
            spells[id] = label
            local category = db.spellCategories[id] or db.spellCategories[key] or db.spellCategories[tostring(id)]
            if categoryNames[category] then
                categories[id] = category
            end
        end
    end
    db.spells = spells
    db.spellCategories = categories
    ConsumablesTimersDB = db
    addon.db = db
end

local inCombat, enteredWorld
local entries = {}
local displaySpec
local observedWeaponImbue
local classImbueSpells = { WARLOCK = 1237152, SHAMAN = 8017, ROGUE = 8679 }
local classImbueSpell

function addon.GetSpellCategory(id)
    return addon.db.spellCategories[id] or "personal"
end

function addon.GetCategoryName(id)
    return categoryNames[id]
end

function addon.SetSpellCategory(id, category)
    if not addon.IsCombat() and addon.db.spells[id] and categoryNames[category] then
        addon.db.spellCategories[id] = category
        addon.RebuildDisplay()
    end
end

function addon.GetSpellIcon(id)
    local icon = C_Spell.GetSpellTexture(id)
    return icon and icon ~= 0 and icon or 134400
end

function addon.IsCombat()
    return inCombat or InCombatLockdown()
end

function addon.SetLocked(locked)
    if addon.IsCombat() then
        return
    end
    addon.db.locked = locked
    addon.SyncLockOption()
    addon.UpdateInteraction()
    addon.Refresh()
end

local function IsMuted(db)
    local _, instance = IsInInstance()
    return (db.disableWorld and db.disableDungeon and db.disableRaid)
        or (instance == "none" and db.disableWorld)
        or (instance == "party" and db.disableDungeon)
        or (instance == "raid" and db.disableRaid)
end

function addon.Refresh()
    if not enteredWorld then
        return
    end
    local db = addon.db
    local combat = addon.IsCombat()
    if not combat and displaySpec ~= addon.GetActiveSpec() then
        addon.RebuildDisplay()
        return
    end
    if #entries == 0 or IsMuted(db) or (combat and db.outOfCombatOnly) then
        addon.HideDisplay()
        return
    end
    local food, timers = addon.ReadAuras(db.spells, GetTime())
    if not db.hideDefaultBuffs then
        timers.wellfed = food
        timers.weapon, timers.imbue = addon.ReadWeapon()
        if timers.imbue and timers.imbue ~= addon.unavailable and not (classImbueSpell or observedWeaponImbue) then
            observedWeaponImbue = true
            addon.RebuildDisplay()
            return
        end
    end
    local showWarning = db.warn and not combat
    local previewWarning = showWarning and not db.locked and addon.OptionsShown()
    addon.Render(entries, timers, combat, showWarning, previewWarning)
end

local function DisplayLabel(key, fallback)
    local label = addon.db.text[key]
    return label ~= "" and label or fallback
end

function addon.GetTrackedSpellIDs()
    local ids = {}
    for id in pairs(addon.db.spells) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

function addon.RebuildDisplay()
    local db = addon.db
    displaySpec = addon.GetActiveSpec()
    local groups = {}
    for _, category in ipairs(addon.categories) do
        groups[category.id] = {}
    end
    local consumables = groups.consumables
    if not db.hideDefaultBuffs then
        consumables[1] = { key = "wellfed", label = DisplayLabel("wellfed", defaults.text.wellfed), icon = 136000,
            click = addon.GetItemClick(addon.GetSelectedItem(displaySpec, "food")) }
        consumables[2] = { key = "weapon", label = DisplayLabel("weapon", defaults.text.weapon),
            icon = "Interface\\Icons\\INV_Potion_105", click = addon.GetItemClick(addon.GetSelectedItem(displaySpec, "weapon"), true) }
        if classImbueSpell or observedWeaponImbue then
            local label = DisplayLabel("imbue", defaults.text.imbue)
            consumables[3] = { key = "imbue", label = label, useResultName = label == defaults.text.imbue,
                icon = classImbueSpell and addon.GetSpellIcon(classImbueSpell) or "Interface\\Icons\\INV_Enchant_DustStrange" }
        end
    end
    local flask = addon.GetItemClick(addon.GetSelectedItem(displaySpec, "flask"))
    if flask then
        consumables[#consumables + 1] = { key = "flask", label = DisplayLabel("flask", defaults.text.flask),
            icon = 134400, click = flask, useOnly = true }
    end

    for _, id in ipairs(addon.GetTrackedSpellIDs()) do
        local label = db.spells[id]
        if label == "" then
            label = C_Spell.GetSpellName(id) or ("Spell " .. id)
        end
        local group = groups[addon.GetSpellCategory(id)]
        group[#group + 1] = { key = id, label = label, icon = addon.GetSpellIcon(id), click = addon.GetSpellClick(id) }
    end
    entries = {}
    for _, category in ipairs(addon.categories) do
        for _, entry in ipairs(groups[category.id]) do
            entry.category = category.id
            entries[#entries + 1] = entry
        end
    end

    addon.LayoutDisplay(entries)
    addon.UpdateInteraction()
    addon.Refresh()
    addon.RefreshTrackingWindow()
end

local function RequestSpell(id)
    if C_Spell.DoesSpellExist(id) and not C_Spell.IsSpellDataCached(id) then
        C_Spell.RequestLoadSpellData(id)
    end
end

function addon.SetTrackedSpell(id, track, category)
    if addon.IsCombat() then
        return false, "ConsumablesTimers is locked during combat."
    end
    if not addon.IsSpellID(id) then
        return false, "Enter a valid spell ID."
    end

    local spells = addon.db.spells
    local tracked = spells[id] ~= nil
    if track == tracked then
        return false, track and "That spell is already tracked." or "That spell is not tracked."
    end

    spells[id] = track and "" or nil
    addon.db.spellCategories[id] = track and categoryNames[category] and category or nil
    if track then
        RequestSpell(id)
    end
    addon.RebuildDisplay()
    return true, (track and "Now tracking spell " or "Removed spell ") .. id .. "."
end

local function Say(text)
    print("|cffefd080ConsumablesTimers|r " .. text)
end

local function ShowHelp()
    Say("/ct opens settings. /ct list shows tracked buffs.")
    Say("/ct tracking opens the tracked spell ID window.")
    Say("/ct add <spellID> or /ct remove <spellID> changes tracked buffs.")
    Say("/ct label <spellID|wellfed|weapon> <text> renames a buff. Omit the text to reset it.")
    Say("/ct unlock or /ct lock changes drag access. /ct resetposition restores both positions.")
end

local function HandleSlash(message)
    local command, arguments = strtrim(message):match("^(%S*)%s*(.*)$")
    command = command:lower()
    local opensSettings = command == "" or command == "options"
    if addon.IsCombat() then
        local warning = "ConsumablesTimers is locked during combat."
        if opensSettings or command == "tracking" then
            warning = opensSettings and "Leave combat to open the settings window."
                or "Leave combat to open the tracking window."
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(warning, 1, 0.25, 0.25, 1)
            end
        end
        Say(warning)
        return
    end
    if command == "help" then
        ShowHelp()
        return
    end
    if command == "list" then
        for _, entry in ipairs(entries) do
            if not entry.useOnly then
                local suffix = type(entry.key) == "number" and " (" .. entry.key .. ")" or ""
                Say(entry.label .. suffix)
            end
        end
        return
    end
    local db = addon.db
    if opensSettings then
        addon.OpenOptions()
    elseif command == "tracking" then
        addon.OpenTrackingWindow()
    elseif command == "add" or command == "remove" then
        local id = addon.ParseSpellID(arguments)
        if not id then
            Say("Usage: /ct " .. command .. " <spellID>")
        else
            local _, feedback = addon.SetTrackedSpell(id, command == "add")
            Say(feedback)
        end
    elseif command == "label" then
        local key, label = arguments:match("^(%S+)%s*(.*)$")
        key = key and key:lower()
        if key == "wellfed" or key == "weapon" then
            db.text[key] = label ~= "" and label or defaults.text[key]
            addon.CloseOptions()
            addon.RebuildDisplay()
        elseif addon.IsSpellID(tonumber(key)) and db.spells[tonumber(key)] then
            db.spells[tonumber(key)] = label
            addon.RebuildDisplay()
        else
            Say("Usage: /ct label <tracked spellID|wellfed|weapon> <text>")
        end
    elseif command == "unlock" or command == "lock" then
        addon.SetLocked(command == "lock")
        Say(db.locked and "Positions locked." or "Drag the timer or warning to move it.")
    elseif command == "resetposition" then
        db.timerPosition = ApplyDefaults(nil, defaults.timerPosition)
        db.warningPosition = ApplyDefaults(nil, defaults.warningPosition)
        addon.RestorePositions()
        addon.Refresh()
    else
        ShowHelp()
    end
end

local function UpdateCombatState()
    if addon.IsCombat() then
        addon.CloseOptions()
        addon.CloseTrackingWindow()
        addon.UpdateInteraction()
        addon.Refresh()
    else
        addon.RefreshBagConsumables()
        addon.RebuildDisplay()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= name then
            return
        end
        self:UnregisterEvent(event)
        LoadDatabase()
        addon.LoadClickSettings()
        classImbueSpell = classImbueSpells[select(2, UnitClass("player"))]
        addon.CreateDisplay()
        addon.RebuildDisplay()

        SLASH_CONSUMABLESTIMERS1 = "/ct"
        SLASH_CONSUMABLESTIMERS2 = "/consumablestimers"
        SlashCmdList.CONSUMABLESTIMERS = HandleSlash

        for _, refreshEvent in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA",
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "SPELL_DATA_LOAD_RESULT",
            "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED",
            "ITEM_DATA_LOAD_RESULT", "PLAYER_LEVEL_UP" }) do
            self:RegisterEvent(refreshEvent)
        end
        self:RegisterUnitEvent("UNIT_AURA", "player")
        self:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
        for id in pairs(addon.db.spells) do
            RequestSpell(id)
        end
        C_Timer.NewTicker(0.5, addon.Refresh)
    elseif event == "PLAYER_ENTERING_WORLD" then
        enteredWorld = true
        inCombat = InCombatLockdown()
        UpdateCombatState()
    elseif event == "PLAYER_LEAVING_WORLD" then
        enteredWorld = false
        addon.HideDisplay()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inCombat = event == "PLAYER_REGEN_DISABLED"
        UpdateCombatState()
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        if arg2 and addon.db.spells[arg1] then
            addon.RebuildDisplay()
        end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" then
        if not addon.IsCombat() then
            addon.RebuildDisplay()
            addon.RefreshClickOptions()
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_LEVEL_UP"
        or (event == "ITEM_DATA_LOAD_RESULT" and arg2 and addon.IsRequestedItem(arg1)) then
        if enteredWorld and not addon.IsCombat() and addon.RefreshBagConsumables(event == "PLAYER_LEVEL_UP" and arg1 or nil) then
            addon.RebuildDisplay()
        else
            addon.Refresh()
        end
        addon.RefreshClickOptions()
    else
        addon.Refresh()
    end
end)
