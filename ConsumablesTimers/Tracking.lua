local _, addon = ...

local unavailable = {}
addon.unavailable = unavailable

-- Known spell IDs can still be queried individually when the client restricts a full scan.
local foodIDs = {
    [19705] = true, [19706] = true, [19708] = true, [19709] = true,
    [19710] = true, [19711] = true, [24799] = true, [1248406] = true,
    [1248688] = true, [1249907] = true, [1302064] = true,
}

local function IsPublic(value)
    return not issecretvalue(value)
end

local function ReadHelpfulAuras()
    if C_Secrets.ShouldAurasBeSecret() then
        return
    end
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
    if ok and IsPublic(auras) and type(auras) == "table" then
        return auras
    end
end

function addon.ReadActiveBuffs(trackedSpells)
    local auras = ReadHelpfulAuras()
    if not auras then
        return
    end
    local buffs, seen = {}, {}
    for _, aura in ipairs(auras) do
        if IsPublic(aura) then
            local id = aura.spellId
            if IsPublic(id) and addon.IsSpellID(id) and not seen[id] and not trackedSpells[id] then
                local name, icon = aura.name, aura.icon
                buffs[#buffs + 1] = {
                    id = id,
                    name = IsPublic(name) and name or nil,
                    icon = IsPublic(icon) and icon ~= 0 and icon or nil,
                }
                seen[id] = true
            end
        end
    end
    table.sort(buffs, function(a, b) return a.id < b.id end)
    return buffs
end

local function ReadAura(aura, now)
    local expires, rate, icon = aura.expirationTime, aura.timeMod, aura.icon
    if not IsPublic(expires) or not IsPublic(rate) or type(expires) ~= "number" then
        return unavailable
    end
    if not IsPublic(icon) then
        icon = nil
    end
    if expires == 0 then
        return { remaining = math.huge, icon = icon }
    end
    if expires > now then
        return { remaining = (expires - now) / (rate and rate > 0 and rate or 1), icon = icon }
    end
end

local function Later(first, second)
    if second and second ~= unavailable and
        (not first or first == unavailable or second.remaining > first.remaining) then
        return second
    end
    return first or second
end

local function ReadSpell(spellID, now)
    if C_Secrets.ShouldSpellAuraBeSecret(spellID) then
        return unavailable
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or not IsPublic(aura) then
        return unavailable
    end
    if aura then
        if not IsPublic(aura.isHelpful) then
            return unavailable
        end
        if aura.isHelpful then
            return ReadAura(aura, now)
        end
    end
end

function addon.ReadAuras(spells, now)
    local food, found = nil, {}
    local auras = ReadHelpfulAuras()
    local incomplete = not auras
    if auras then
        local foodName = C_Spell.GetSpellName(19708) or "Well Fed"
        for _, aura in ipairs(auras) do
            if IsPublic(aura) then
                local spellID, name = aura.spellId, aura.name
                if IsPublic(spellID) and type(spellID) == "number" then
                    if foodIDs[spellID] or (IsPublic(name) and name == foodName) then
                        foodIDs[spellID] = true
                        food = Later(food, ReadAura(aura, now))
                    elseif not IsPublic(name) then
                        incomplete = true
                    end
                    if spells[spellID] then
                        found[spellID] = Later(found[spellID], ReadAura(aura, now))
                    end
                else
                    incomplete = true
                    if IsPublic(name) and name == foodName then
                        food = Later(food, ReadAura(aura, now))
                    end
                end
            else
                incomplete = true
            end
        end
    else
        -- A missing result for these IDs can't rule out all localized food variants.
        food = unavailable
        for spellID in pairs(foodIDs) do
            food = Later(food, ReadSpell(spellID, now))
        end
    end

    if incomplete then
        food = food or unavailable
        for spellID in pairs(spells) do
            if not found[spellID] then
                found[spellID] = ReadSpell(spellID, now)
            end
        end
    end
    return food, found
end

local weaponSlots = { Enum.WeaponSlot.MainHand, Enum.WeaponSlot.OffHand, Enum.WeaponSlot.Ranged }
local temporary = Enum.ItemEnchantType.Temporary
local imbue = Enum.ItemEnchantType.Imbue

local stoneNamesByEnchant = {
    [1803] = "Firestone", [1823] = "Firestone", [1824] = "Firestone", [1825] = "Firestone",
    [8059] = "Spellstone", [8060] = "Spellstone", [8061] = "Spellstone",
}
local stoneNamesByIcon = { [134085] = "Firestone", [134131] = "Spellstone" }

local function ReadWeaponTimer(enchant, kind)
    local milliseconds = enchant.timeLeft
    if not IsPublic(milliseconds) then
        return unavailable
    end
    if type(milliseconds) ~= "number" or milliseconds <= 0 then
        return
    end
    local icon = enchant.enchantIconID
    if not IsPublic(icon) or icon == 0 then
        icon = nil
    end
    local label
    if kind == imbue then
        local id = enchant.enchantID
        label = (IsPublic(id) and stoneNamesByEnchant[id]) or stoneNamesByIcon[icon]
    end
    return { remaining = milliseconds / 1000, icon = icon, name = label }
end

function addon.ReadWeapon()
    local oilTimer, imbueTimer
    for _, slot in ipairs(weaponSlots) do
        local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, slot)
        if ok and IsPublic(enchants) and type(enchants) == "table" then
            for _, enchant in ipairs(enchants) do
                if not IsPublic(enchant) or not IsPublic(enchant.hasEnchant) or not IsPublic(enchant.enchantType) then
                    oilTimer, imbueTimer = oilTimer or unavailable, imbueTimer or unavailable
                elseif enchant.hasEnchant then
                    local kind = enchant.enchantType
                    if kind == temporary then
                        oilTimer = Later(oilTimer, ReadWeaponTimer(enchant, kind))
                    elseif kind == imbue then
                        imbueTimer = Later(imbueTimer, ReadWeaponTimer(enchant, kind))
                    end
                end
            end
        else
            oilTimer, imbueTimer = oilTimer or unavailable, imbueTimer or unavailable
        end
    end
    return oilTimer, imbueTimer
end
