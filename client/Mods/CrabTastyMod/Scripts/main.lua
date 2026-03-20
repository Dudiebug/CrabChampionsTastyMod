-- perk_tastyorange_mod.lua
-- Gives TastyOrange a custom "+3% damage per weapon mod owned" behavior.
--
-- HOW IT WORKS:
--   No native PerkType exists for "counts weapon mods", so we use
--   PerkType=72 (Collector) as a C++ host and trick it with math:
--
--     Collector formula:  damage_bonus = BaseBuff × perkCount
--     We want:            damage_bonus = modCount  × DAMAGE_PER_MOD × tastyLevel
--     Therefore:          BaseBuff     = modCount  × DAMAGE_PER_MOD × tastyLevel / perkCount
--
--   tastyLevel = how many times TastyOrange appears in the Perks array (i.e. perk level).
--   Updated every TICK_MS so it stays accurate as you pick up / lose items.
--   This change is local only — DataAssets are per-process, no sync needed.

local DAMAGE_PER_MOD    = 3.0   -- % per weapon mod per level (change this to adjust scaling)
local PERK_TYPE_HOST    = 72    -- Collector: game computes BaseBuff × perkCount
local TICK_MS           = 500   -- how often to recalculate (ms)

-- ──────────────────────────────────────────────────────────────────────────────
-- Helpers (self-contained so this file doesn't depend on main.lua load order)
-- ──────────────────────────────────────────────────────────────────────────────

local tastyDA   = nil   -- cached DA_Perk_TastyOrange reference
local ptSet     = false -- true once PerkType has been written
local descSet   = false -- true once Description has been written

local PERK_DESC = "Damage increased by 3% for each weapon mod level that you have."

-- Field names to try for the perk description (most likely first).
local DESC_FIELDS = { "Description", "PerkDescription", "DescriptionText", "Tooltip", "FlavorText" }

local function findTastyDA()
    -- Return cached if still valid
    if tastyDA then
        local ok, v = pcall(function() return tastyDA:IsValid() end)
        if ok and v then return tastyDA end
        print("[TastyMod] Cached DA became invalid — rescanning.\n")
        tastyDA = nil
        ptSet   = false
    end
    local all = FindAllOf("CrabPerkDA")
    if not all then
        print("[TastyMod] FindAllOf(CrabPerkDA) returned nil — no DAs loaded yet.\n")
        return nil
    end
    print("[TastyMod] Scanning " .. #all .. " CrabPerkDA(s) for TastyOrange...\n")
    for _, da in ipairs(all) do
        local ok, n = pcall(function() return da:GetFullName() end)
        if ok and n and tostring(n):lower():find("tastyorange") then
            print("[TastyMod] Found DA: " .. tostring(n) .. "\n")
            tastyDA = da
            return da
        end
    end
    print("[TastyMod] TastyOrange DA not found in scan.\n")
    return nil
end

-- Count elements in a TArray on a UObject without crashing on struct arrays.
local function countArr(obj, propName)
    local n = 0
    pcall(function()
        local arr = obj:GetPropertyValue(propName)
        if arr then arr:ForEach(function() n = n + 1 end) end
    end)
    return n
end

-- Count how many times TastyOrange appears in the Perks array (= perk level).
-- UE4SS TArray-of-structs: ForEach yields a wrapper; elem:get() unwraps the struct.
local function countTastyLevel(ps)
    if not tastyDA then return 0 end
    local count = 0
    pcall(function()
        local arr = ps:GetPropertyValue("Perks")
        if not arr then return end
        arr:ForEach(function(_, elem)
            pcall(function()
                if not elem:get():IsValid() then return end
                local ok, da = pcall(function() return elem:get().PerkDA end)
                if not ok or not da then return end
                local okeq, same = pcall(function() return da == tastyDA end)
                if okeq and same then count = count + 1 end
            end)
        end)
    end)
    return count
end

local function getLocalPS()
    local pc = FindFirstOf("CrabPC")
    if not pc then return nil end
    local okv = pcall(function() return pc:IsValid() end)
    if not okv then return nil end
    local ok, ps = pcall(function() return pc:GetPropertyValue("PlayerState") end)
    if not ok or not ps then return nil end
    local okps = pcall(function() return ps:IsValid() end)
    return okps and ps or nil
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Main tick
-- ──────────────────────────────────────────────────────────────────────────────

local function tick()
    print("[TastyMod] Tick...\n")

    local da = findTastyDA()
    if not da then
        print("[TastyMod] DA not ready — retrying in " .. TICK_MS .. "ms.\n")
        ExecuteWithDelay(TICK_MS, tick)
        return
    end

    -- Step 1: Set PerkType = Collector once (C++ host behavior).
    if not ptSet then
        print("[TastyMod] Attempting to set PerkType → " .. PERK_TYPE_HOST .. "...\n")
        local ok, err = pcall(function()
            da:SetPropertyValue("PerkType", PERK_TYPE_HOST)
        end)
        if ok then
            ptSet = true
            print("[TastyMod] PerkType → 72 (Collector host). Now computing BaseBuff dynamically.\n")
        else
            print("[TastyMod] Could not set PerkType: " .. tostring(err) .. "\n")
        end
    end

    -- Step 1b: Overwrite the perk description once.
    if not descSet then
        local wrote = false
        for _, field in ipairs(DESC_FIELDS) do
            local ok, err = pcall(function()
                da:SetPropertyValue(field, PERK_DESC)
            end)
            if ok then
                descSet = true
                wrote   = true
                print("[TastyMod] Description written via field '" .. field .. "'.\n")
                break
            else
                print("[TastyMod] Field '" .. field .. "' failed: " .. tostring(err) .. "\n")
            end
        end
        if not wrote then
            print("[TastyMod] WARNING: Could not write description — none of the candidate fields worked.\n")
            descSet = true  -- stop retrying, don't spam
        end
    end

    -- Step 2: Recalculate BaseBuff = modCount × DAMAGE_PER_MOD × tastyLevel / perkCount.
    local ps = getLocalPS()
    if not ps then
        print("[TastyMod] PlayerState not found — skipping BaseBuff update.\n")
        ExecuteWithDelay(TICK_MS, tick)
        return
    end

    local modCount   = countArr(ps, "WeaponMods")
    local perkCount  = countArr(ps, "Perks")
    local tastyLevel = countTastyLevel(ps)
    print("[TastyMod] modCount=" .. modCount .. "  perkCount=" .. perkCount .. "  tastyLevel=" .. tastyLevel .. "\n")

    if perkCount <= 0 then
        print("[TastyMod] perkCount is 0 — skipping BaseBuff update.\n")
    elseif tastyLevel <= 0 then
        print("[TastyMod] TastyOrange not equipped — skipping BaseBuff update.\n")
    else
        local newBuff = (modCount * DAMAGE_PER_MOD * tastyLevel) / perkCount
        print("[TastyMod] Setting BaseBuff → " .. string.format("%.4f", newBuff) ..
              "  (" .. modCount .. " mods × " .. DAMAGE_PER_MOD .. "% × lv" .. tastyLevel ..
              " / " .. perkCount .. " perks)\n")
        local ok, err = pcall(function() da:SetPropertyValue("BaseBuff", newBuff) end)
        if not ok then
            print("[TastyMod] Failed to set BaseBuff: " .. tostring(err) .. "\n")
        end
    end

    ExecuteWithDelay(TICK_MS, tick)
end

-- Short initial delay so DataAssets finish streaming before the first scan.
ExecuteWithDelay(500, tick)

print("[TastyMod] Loaded — TastyOrange: +" .. DAMAGE_PER_MOD .. "% damage per weapon mod per level owned.\n")
