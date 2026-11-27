local _, addon = ...

local characterSettings
local requestedItems = {}
local consumableSubclasses = Enum.ItemConsumableSubclass
local defaults = { food = "auto", flask = "auto", weapon = "auto" }
local bagItems = { food = {}, flask = {}, weapon = {} }
local autoItems = {}

-- Forever also classifies some of these as trade goods or generic consumables.
local weaponEnhancements = {
    -- Shadow Oil and Frost Oil
    [3824] = true, [3829] = true,
    -- Mana and wizard oils
    [20744] = true, [20745] = true, [20746] = true, [20747] = true,
    [20748] = true, [20749] = true, [20750] = true,
    -- Sharpening stones
    [2862] = true, [2863] = true, [2871] = true, [7964] = true,
    [12404] = true, [18262] = true, [287980] = true,
    -- Weightstones
    [3239] = true, [3240] = true, [3241] = true, [7965] = true, [12643] = true,
}

local function IsItemChoice(kind, choice)
    return choice == "none" or (choice == "auto" and defaults[kind] == "auto") or addon.IsSpellID(choice)
end

function addon.LoadClickSettings()
    characterSettings = type(ConsumablesTimersCharacterDB) == "table" and ConsumablesTimersCharacterDB or {}
    for spec = 1, 2 do
        local choices = type(characterSettings[spec]) == "table" and characterSettings[spec] or {}
        for kind in pairs(defaults) do
            if not IsItemChoice(kind, choices[kind]) then
                choices[kind] = nil
            end
        end
        characterSettings[spec] = choices
    end
    ConsumablesTimersCharacterDB = characterSettings
end

function addon.HasSecondarySpec()
    return (GetNumSpecGroups() or 0) > 1
end

function addon.GetActiveSpec()
    return C_SpecializationInfo.GetActiveSpecGroup() == 2 and 2 or 1
end

function addon.GetItemChoice(spec, kind)
    return characterSettings[spec][kind] or defaults[kind]
end

function addon.GetSelectedItem(spec, kind)
    local choice = addon.GetItemChoice(spec, kind)
    if choice == "auto" then
        return autoItems[kind]
    end
    if choice ~= "none" then
        return choice
    end
end

function addon.GetAutomaticItem(kind)
    return autoItems[kind]
end

function addon.SetItemChoice(spec, kind, choice)
    if addon.IsCombat() or (spec == 2 and not addon.HasSecondarySpec()) or not IsItemChoice(kind, choice) then
        return
    end
    if addon.GetItemChoice(spec, kind) == choice then
        return
    end
    characterSettings[spec][kind] = choice
    addon.RebuildDisplay()
end

function addon.GetBagCount(id)
    local count = C_Item.GetItemCount(id)
    if not issecretvalue(count) and type(count) == "number" then
        return count
    end
    return 0
end

local function GetConsumableInfo(id)
    local name, _, _, _, requiredLevel = C_Item.GetItemInfo(id)
    if (not name or requiredLevel == nil) and not requestedItems[id] then
        requestedItems[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    return name and name ~= "" and name or ("Item " .. id), requiredLevel
end

function addon.GetConsumableName(id)
    return (GetConsumableInfo(id))
end

function addon.IsRequestedItem(id)
    return requestedItems[id] == true
end

local function GetConsumableKind(id, drinkName)
    if weaponEnhancements[id] then
        return "weapon"
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    if classID ~= Enum.ItemClass.Consumable then
        return
    end
    if subclassID == consumableSubclasses.Flasksphials then
        return "flask"
    end
    if subclassID == consumableSubclasses.ItemenhancementTemporary then
        return "weapon"
    end
    if subclassID == consumableSubclasses.Fooddrink then
        local spellName, spellID = C_Item.GetItemSpell(id)
        if spellID ~= 430 and (not drinkName or spellName ~= drinkName) then
            return "food"
        end
    end
end

local function ScanBagConsumables()
    local choices = { food = {}, flask = {}, weapon = {} }
    local seen = {}
    local drinkName = C_Spell.GetSpellName(430)
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if not issecretvalue(id) and id and not seen[id] then
                seen[id] = true
                local kind = GetConsumableKind(id, drinkName)
                if kind then
                    local name, requiredLevel = GetConsumableInfo(id)
                    local items = choices[kind]
                    items[#items + 1] = { id = id, name = name, requiredLevel = requiredLevel }
                end
            end
        end
    end
    for _, items in pairs(choices) do
        table.sort(items, function(a, b)
            if a.name == b.name then
                return a.id < b.id
            end
            return a.name < b.name
        end)
    end
    return choices
end

function addon.RefreshBagConsumables(level)
    bagItems = ScanBagConsumables()
    level = level or UnitLevel("player")
    if issecretvalue(level) or type(level) ~= "number" then
        level = 0
    end
    local changed = false
    for kind in pairs(defaults) do
        local best, bestLevel = nil, -1
        for _, item in ipairs(bagItems[kind]) do
            local required = item.requiredLevel
            if required and required <= level and required > bestLevel and addon.GetBagCount(item.id) > 0 then
                best, bestLevel = item.id, required
            end
        end
        changed = changed or best ~= autoItems[kind]
        autoItems[kind] = best
    end
    return changed
end

function addon.GetBagConsumables(kind)
    return bagItems[kind]
end

function addon.GetItemClick(id, targetsWeapon)
    if id then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
        return { itemID = id, icon = icon ~= 0 and icon or nil, targetsWeapon = targetsWeapon }
    end
end

function addon.GetSpellClick(id)
    if addon.IsCombat() or not C_SpellBook.IsSpellKnown(id) or not C_Spell.IsSpellHelpful(id)
        or C_Spell.IsSpellPassive(id) then
        return
    end
    return { spellID = id }
end

local function CreateActionButton(row)
    -- Blizzard's template only dispatches user clicks outside combat lockdown.
    local button = CreateFrame("Button", nil, row, "InsecureActionButtonTemplate")
    button:SetAllPoints(row.icon)
    button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", function(self)
        if addon.IsCombat() then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            GameTooltip:SetItemByID(self.itemID)
            if self.targetsWeapon then
                GameTooltip:AddLine("Left-click to apply to main hand. Right-click to apply to off hand.", 1, 1, 1, true)
            end
        else
            GameTooltip:SetSpellByID(self.spellID)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnHide", button:GetScript("OnLeave"))
    return button
end

function addon.UpdateRowClick(row, click, enabled)
    local button = row.action
    if not enabled or not click then
        if button then
            button:Hide()
        end
        return
    end
    if not button then
        button = CreateActionButton(row)
        row.action = button
    end
    if button.itemID ~= click.itemID or button.spellID ~= click.spellID or button.targetsWeapon ~= click.targetsWeapon then
        button:SetAttribute("type1", click.itemID and "item" or "spell")
        button:SetAttribute("item1", click.itemID and "item:" .. click.itemID or nil)
        button:SetAttribute("spell1", click.spellID)
        button:SetAttribute("unit", click.spellID and "player" or nil)
        if click.targetsWeapon then
            button:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
            button:SetAttribute("target-slot1", INVSLOT_MAINHAND or 16)
            button:SetAttribute("type2", "item")
            button:SetAttribute("item2", "item:" .. click.itemID)
            button:SetAttribute("target-slot2", INVSLOT_OFFHAND or 17)
        else
            button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
            button:SetAttribute("target-slot1", nil)
            button:SetAttribute("type2", nil)
            button:SetAttribute("item2", nil)
            button:SetAttribute("target-slot2", nil)
        end
        button.itemID, button.spellID = click.itemID, click.spellID
        button.targetsWeapon = click.targetsWeapon
    end
    button:Show()
end
