local _, addon = ...

local characterSettings
local requestedItems = {}
local consumableSubclasses = Enum.ItemConsumableSubclass

function addon.LoadClickSettings()
    characterSettings = type(ConsumablesTimersCharacterDB) == "table" and ConsumablesTimersCharacterDB or {}
    for spec = 1, 2 do
        local choices = type(characterSettings[spec]) == "table" and characterSettings[spec] or {}
        for _, kind in ipairs({ "food", "flask" }) do
            if not addon.IsSpellID(choices[kind]) then
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

function addon.GetSelectedItem(spec, kind)
    return characterSettings[spec][kind]
end

function addon.SetSelectedItem(spec, kind, id)
    if addon.IsCombat() or (spec == 2 and not addon.HasSecondarySpec()) or (id and not addon.IsSpellID(id)) then
        return
    end
    if characterSettings[spec][kind] == id then
        return
    end
    characterSettings[spec][kind] = id
    addon.RebuildDisplay()
end

function addon.GetBagCount(id)
    local count = C_Item.GetItemCount(id)
    if not issecretvalue(count) and type(count) == "number" then
        return count
    end
    return 0
end

function addon.GetConsumableName(id)
    local name = C_Item.GetItemNameByID(id)
    if name and name ~= "" then
        return name
    end
    if not requestedItems[id] then
        requestedItems[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    return "Item " .. id
end

local function GetConsumableKind(id, drinkName)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    if classID ~= Enum.ItemClass.Consumable then
        return
    end
    if subclassID == consumableSubclasses.Flasksphials then
        return "flask"
    end
    if subclassID == consumableSubclasses.Fooddrink then
        local spellName, spellID = C_Item.GetItemSpell(id)
        if spellID ~= 430 and (not drinkName or spellName ~= drinkName) then
            return "food"
        end
    end
end

function addon.ScanBagConsumables()
    local choices = { food = {}, flask = {} }
    local seen = {}
    local drinkName = C_Spell.GetSpellName(430)
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if not issecretvalue(id) and id and not seen[id] then
                seen[id] = true
                local kind = GetConsumableKind(id, drinkName)
                if kind then
                    local items = choices[kind]
                    items[#items + 1] = { id = id, name = addon.GetConsumableName(id) }
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

function addon.GetItemClick(id)
    if id then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
        return { itemID = id, icon = icon ~= 0 and icon or nil }
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
    if button.itemID ~= click.itemID or button.spellID ~= click.spellID then
        button:SetAttribute("type1", click.itemID and "item" or "spell")
        button:SetAttribute("item1", click.itemID and "item:" .. click.itemID or nil)
        button:SetAttribute("spell1", click.spellID)
        button:SetAttribute("unit", click.spellID and "player" or nil)
        button.itemID, button.spellID = click.itemID, click.spellID
    end
    button:Show()
end
