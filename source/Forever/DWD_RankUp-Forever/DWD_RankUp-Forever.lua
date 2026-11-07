local ADDON, A = ...
local frame = CreateFrame("Frame", "DWD_RankUpForeverFrame")
A.frame, A.version = frame, "1.3.0-forever.2"
A.known, A.pending = {}, {}
A.ready, A.baseline = false, false
local MAX_SLOTS = 120

local function say(message) print("|cff00ff88DWD RankUp|r " .. message) end
local function secret(value) return type(issecretvalue) == "function" and issecretvalue(value) end
local function public(value) if not secret(value) then return value end end
local function read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return public(value) end
end
local function number(value) return not secret(value) and type(value) == "number" and value == value end
local function rank(value)
    if secret(value) or type(value) ~= "string" then return 0 end
    return tonumber(value:match("(%d+)")) or 0
end

function A:DB()
    local store = DWD_RankUpForeverStore
    if type(store) ~= "table" then store = {} DWD_RankUpForeverStore = store end
    if type(store.characters) ~= "table" then store.characters = {} end
    local key = DWD_ForeverIdentity.Key(false)
    local db = DWD_ForeverIdentity.Adopt(store.characters, key)
    if type(db) ~= "table" then db = {} store.characters[key] = db end
    for k, v in pairs({enabled = true, addNew = true, debug = false, firstSlot = 1, lastSlot = MAX_SLOTS}) do
        if type(db[k]) ~= type(v) then db[k] = v end
    end
    if db.firstSlot < 1 or db.firstSlot > MAX_SLOTS or db.firstSlot ~= math.floor(db.firstSlot) then db.firstSlot = 1 end
    if db.lastSlot < db.firstSlot or db.lastSlot > MAX_SLOTS or db.lastSlot ~= math.floor(db.lastSlot) then db.lastSlot = MAX_SLOTS end
    -- Preserve an explicitly narrowed range from older versions. The former
    -- 1-120 default is now the visible buttons, including their stance page.
    if db.placement ~= "visible" and db.placement ~= "range" then
        db.placement = (db.firstSlot ~= 1 or db.lastSlot ~= MAX_SLOTS) and "range" or "visible"
    end
    self.db = db
    return db
end

local function spellName(id)
    if not number(id) then return end
    local info = C_Spell and read(C_Spell.GetSpellInfo, id)
    if type(info) == "table" then
        local name = public(info.name)
        if type(name) == "string" and name ~= "" then return name end
    end
    local name = read(GetSpellInfo, id)
    if type(name) == "string" and name ~= "" then return name end
end

local function spellRank(id, fallback)
    local value = C_Spell and read(C_Spell.GetSpellSubtext, id)
    if value == nil then value = read(GetSpellSubtext, id) end
    if (value == nil or value == "") and type(fallback) == "string" and fallback ~= "" then value = fallback end
    if value == nil and type(GetSpellInfo) == "function" then
        local ok, _, subtext = pcall(GetSpellInfo, id)
        if ok then value = public(subtext) end
    end
    return rank(value)
end

local function inCombat()
    -- A failed/restricted combat check never grants permission to edit bars.
    return read(InCombatLockdown) ~= false
end

local function action(slot)
    if type(GetActionInfo) ~= "function" then return nil, nil, false end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or secret(kind) or secret(id) then return nil, nil, false end
    return kind, id, true
end

local function cursor()
    if type(GetCursorInfo) ~= "function" then return nil, false end
    local ok, kind, _, _, id = pcall(GetCursorInfo)
    if not ok or secret(kind) then return nil, false end
    return kind, true, public(id)
end

function A:BuildBook()
    local highest, seen, complete = {}, 0, true
    local modern = C_SpellBook and type(C_SpellBook.GetNumSpellBookSkillLines) == "function"
        and type(C_SpellBook.GetSpellBookSkillLineInfo) == "function"
        and type(C_SpellBook.GetSpellBookItemInfo) == "function"
        and Enum and Enum.SpellBookSpellBank and Enum.SpellBookItemType
    local bank = modern and Enum.SpellBookSpellBank.Player or BOOKTYPE_SPELL or "spell"
    local count = modern and read(C_SpellBook.GetNumSpellBookSkillLines) or read(GetNumSpellTabs)
    if not number(count) or count < 1 or count > 100 then return nil end
    for tab = 1, count do
        local offset, total
        if modern then
            local line = read(C_SpellBook.GetSpellBookSkillLineInfo, tab)
            if type(line) == "table" then offset, total = public(line.itemIndexOffset), public(line.numSpellBookItems) end
        elseif type(GetSpellTabInfo) == "function" then
            local ok, _, _, off, num = pcall(GetSpellTabInfo, tab)
            if ok then offset, total = public(off), public(num) end
        end
        if not number(offset) or not number(total) or offset < 0 or total < 0 or offset + total > 5000 then
            complete = false
        else
            for slot = offset + 1, offset + total do
                local id, name, subtext, passive, offspec, isSpell
                if modern then
                    local info = read(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                    if type(info) == "table" then
                        local kind = public(info.itemType)
                        isSpell = kind == Enum.SpellBookItemType.Spell
                        id = public(info.spellID)
                        if not number(id) then id = public(info.actionID) end
                        name, subtext = public(info.name), public(info.subName)
                        passive, offspec = public(info.isPassive), public(info.isOffSpec)
                        if secret(info.itemType) or secret(info.isPassive) or secret(info.isOffSpec) then isSpell = false complete = false end
                    else complete = false end
                elseif type(GetSpellBookItemInfo) == "function" then
                    local ok, kind, spell = pcall(GetSpellBookItemInfo, slot, bank)
                    if ok and not secret(kind) and not secret(spell) then isSpell, id = kind == "SPELL", spell
                    else complete = false end
                end
                if isSpell and number(id) and not offspec then
                    name = type(name) == "string" and name ~= "" and name or spellName(id)
                    if passive == nil then passive = C_Spell and read(C_Spell.IsSpellPassive, id) end
                    if passive == nil then passive = read(IsPassiveSpell, id) end
                    if passive == nil and modern then passive = read(C_SpellBook.IsSpellBookItemPassive, slot, bank) end
                    if name and type(passive) == "boolean" then
                        seen = seen + 1
                        local r = spellRank(id, subtext)
                        local old = highest[name]
                        if not old or r > old.rank then highest[name] = {id = id, name = name, rank = r, passive = passive, slot = slot, bank = bank} end
                    else complete = false end
                end
            end
        end
    end
    -- An empty/partial spellbook during login or data loading is not a new
    -- baseline. Keeping the previous one prevents accidental mass auto-fill.
    if not complete or seen == 0 then return nil end
    return highest, modern and "Forever C_SpellBook" or "legacy spellbook"
end

local function buttonSlot(button)
    if not button or read(button.IsVisible, button) ~= true then return end
    if type(button.GetEffectiveAlpha) == "function" then
        local alpha = read(button.GetEffectiveAlpha, button)
        if not number(alpha) or alpha <= 0 then return end
    end
    local slot
    if type(button.GetAction) == "function" then
        local ok, kind, id = pcall(button.GetAction, button)
        if not ok or secret(kind) or secret(id) or kind ~= "action" then return end
        slot = id
    else
        slot = read(button.GetPagedID, button)
        if not number(slot) then slot = read(ActionButton_GetPagedID, button) end
        if not number(slot) then slot = read(button.GetAttribute, button, "action") end
        if not number(slot) then slot = public(button.action) end
    end
    if number(slot) and slot >= 1 and slot <= MAX_SLOTS and slot == math.floor(slot) then return slot end
end

function A:VisibleSlots()
    local result, seen, frames = {}, {}, {}
    local function add(button, label)
        if not button or frames[button] then return end
        frames[button] = true
        local slot = buttonSlot(button)
        if slot and not seen[slot] then
            seen[slot] = true
            result[#result + 1] = {slot = slot, button = button,
                label = label .. " (action slot " .. slot .. ")"}
        end
    end
    -- BT4 button IDs describe the visual bar, not the slot it currently
    -- displays. GetAction resolves its active secure stance/paging state.
    for i = 1, MAX_SLOTS do
        add(_G["BT4Button" .. i], ("Bartender bar %d, button %d"):format(math.floor((i - 1) / 12) + 1, (i - 1) % 12 + 1))
    end
    local prefixes = {"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button"}
    for _, prefix in ipairs(prefixes) do
        for i = 1, 12 do add(_G[prefix .. i], prefix == "ActionButton" and ("main bar, button " .. i) or (prefix .. i)) end
    end
    -- Other LibActionButton consumers use the same public button methods.
    if LibStub then
        local ok, lib = pcall(LibStub, "LibActionButton-1.0", true)
        local buttons = ok and lib and read(lib.GetAllButtons, lib)
        if type(buttons) == "table" then
            local extra = {}
            for button in pairs(buttons) do
                local name = read(button.GetName, button)
                if type(name) == "string" then extra[#extra + 1] = {button = button, name = name} end
            end
            table.sort(extra, function(x, y) return x.name < y.name end)
            for _, item in ipairs(extra) do add(item.button, item.name) end
        end
    end
    return result
end

function A:OnBars(name, visibleOnly)
    local slots = visibleOnly and self:VisibleSlots() or nil
    for index = 1, slots and #slots or MAX_SLOTS do
        local slot = slots and slots[index].slot or index
        local kind, id, ok = action(slot)
        if not ok then return nil end
        if kind == "spell" and spellName(id) == name then return true end
    end
    return false
end

function A:EmptySlot(visibleOnly)
    local db = self:DB()
    if visibleOnly then
        for _, target in ipairs(self:VisibleSlots()) do
            local kind, _, ok = action(target.slot)
            if ok and kind == nil then return target.slot, target end
        end
        return
    end
    for slot = db.firstSlot, db.lastSlot do
        local kind, _, ok = action(slot)
        if ok and kind == nil then return slot end
    end
end

function A:UpgradePlan(highest)
    local plan = {}
    for slot = 1, MAX_SLOTS do
        local kind, id, ok = action(slot)
        if ok and kind == "spell" and number(id) then
            local name = spellName(id)
            local best = name and highest[name]
            local have = spellRank(id)
            -- Do not turn temporarily missing rank text into Rank 0 and then
            -- accidentally replace a spell whose actual rank is unknown.
            if best and not best.passive and have > 0 and have < best.rank then
                plan[#plan + 1] = {slot = slot, previous = id, best = best}
            end
        end
    end
    return plan
end

function A:Place(best, slot, expectedKind, expectedID, target)
    if inCombat() then return false, "combat" end
    local held, cursorOK = cursor()
    if not cursorOK or held ~= nil then return false, "cursor" end
    local kind, id, readable = action(slot)
    if not readable or kind ~= expectedKind or id ~= expectedID then return false, "slot changed" end
    if target and buttonSlot(target.button) ~= slot then return false, "visible bar page changed" end
    if type(PlaceAction) ~= "function" or type(ClearCursor) ~= "function" then return false, "action-bar API unavailable" end
    local pickers = {
        function() if C_Spell and type(C_Spell.PickupSpell) == "function" then C_Spell.PickupSpell(best.id) end end,
        function()
            if C_SpellBook and type(C_SpellBook.PickupSpellBookItem) == "function" then
                local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or best.bank
                C_SpellBook.PickupSpellBookItem(best.slot, bank)
            end
        end,
        function() if type(PickupSpell) == "function" then PickupSpell(best.id) end end,
        function() if type(PickupSpellBookItem) == "function" then PickupSpellBookItem(best.slot, BOOKTYPE_SPELL or "spell") end end,
    }
    local picked = false
    for _, pickup in ipairs(pickers) do
        local ok = pcall(pickup)
        local payload
        held, cursorOK, payload = cursor()
        if not cursorOK then return false, "cursor unavailable" end
        if held == "spell" then
            if number(payload) and payload ~= best.id then pcall(ClearCursor) return false, "wrong spell picked up" end
            if ok then picked = true break end
            pcall(ClearCursor)
            return false, "spell pickup blocked"
        elseif held ~= nil then return false, "cursor changed" end
    end
    if not picked then return false, "spell pickup unavailable or blocked" end
    -- Another addon may react synchronously during pickup. Recheck the slot,
    -- combat state and cursor immediately before replacing anything.
    kind, id, readable = action(slot)
    held, cursorOK = cursor()
    if inCombat() or not readable or kind ~= expectedKind or id ~= expectedID or not cursorOK or held ~= "spell"
        or (target and buttonSlot(target.button) ~= slot) then
        if cursorOK and held == "spell" then pcall(ClearCursor) end
        return false, "slot or cursor changed"
    end
    local ok, err = pcall(PlaceAction, slot)
    local actualKind, actualID, actualOK = action(slot)
    -- Placement can leave the displaced lower rank on our cursor; discard only
    -- that spell cursor. Never clear an item/macro somebody else put there.
    held, cursorOK = cursor()
    if cursorOK and held == "spell" then pcall(ClearCursor) end
    if not ok then return false, "placement blocked: " .. tostring(err) end
    if not actualOK or actualKind ~= "spell" then return false, "placement could not be verified" end
    if actualID ~= best.id and (spellName(actualID) ~= best.name or spellRank(actualID) < best.rank) then
        return false, "placement could not be verified"
    end
    if target and buttonSlot(target.button) ~= slot then return false, "spell placed but visible bar page changed" end
    return true
end

function A:Request(reason)
    if not self.ready then return end
    self.requested = true
    if reason == "learn" then self.learn = true end
    if reason == "manual" then self.manual = true self.blocked = nil self.lastError = nil end
    self.delay = math.min(self.delay or 0.35, 0.35)
    self.waitingSlot = false
end

function A:Fail(reason)
    self.lastError = reason
    self.blocked = true
    say("Could not change the action bar (" .. reason .. "). Use /dwdrank update to retry when out of combat.")
end

function A:Process()
    if inCombat() then self.waitingCombat = true return end
    self.waitingCombat = false
    local db = self:DB()
    local highest, api = self:BuildBook()
    if not highest then self.requested = true self.delay = 0.5 self.lastStatus = "Waiting for complete spellbook data" return end
    self.api = api
    if self.requested then
        if db.debug then say("Spellbook scan using " .. api .. "; learn event " .. tostring(not not self.learn) .. ".") end
        if self.baseline and self.learn and db.enabled and db.addNew then
            for name, entry in pairs(highest) do
                if self.known[name] == nil and not entry.passive then self.pending[name] = true end
            end
        end
        self.known = {}
        for name, entry in pairs(highest) do self.known[name] = entry.rank end
        self.baseline = true
        self.requested, self.learn = false, false
        self.wantUpgrade = db.enabled or self.manual
    end
    if not db.enabled then self.pending = {}
    elseif not db.addNew then
        for name, intent in pairs(self.pending) do if intent ~= "manual" then self.pending[name] = nil end end
    end
    if self.blocked then return end
    local held, cursorOK = cursor()
    if not cursorOK or held ~= nil then self.waitingCursor = true self.delay = 0.5 return end
    self.waitingCursor = false
    local changed, added = 0, 0
    if self.wantUpgrade and (db.enabled or self.manual) then
        for _, entry in ipairs(self:UpgradePlan(highest)) do
            local ok, reason = self:Place(entry.best, entry.slot, "spell", entry.previous)
            if not ok then self:Fail(reason) return end
            changed = changed + 1
            say(("Upgraded %s to Rank %d on slot %d."):format(entry.best.name, entry.best.rank, entry.slot))
        end
    end
    self.wantUpgrade = false
    if self.manual and changed == 0 then say("No outdated spell ranks found on your bars.") end
    self.manual = false
    if db.enabled and (db.addNew or next(self.pending)) then
        local names = {}
        for name in pairs(self.pending) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local best = highest[name]
            local visibleOnly = self.pending[name] == "manual" or db.placement == "visible"
            local onBars = self:OnBars(name, visibleOnly)
            if not best or best.passive or onBars == true then self.pending[name] = nil
            elseif onBars == nil then self:Fail("action slots unavailable") return
            else
                local slot, target = self:EmptySlot(visibleOnly)
                if not slot then
                    self.waitingSlot = true
                    if not self.fullNotified then
                        say(visibleOnly and "No empty visible action buttons; ability queued. Show a bar or free a button, then use /dwdrank update."
                            or "No empty slots in the placement range; newly learned abilities are queued until a slot is freed.")
                        self.fullNotified = true
                    end
                    break
                end
                local ok, reason = self:Place(best, slot, nil, nil, target)
                if not ok then self:Fail(reason) return end
                self.pending[name] = nil
                added = added + 1
                say(target and ("Added %s to %s."):format(name, target.label)
                    or ("Added %s to action slot %d (configured range; may be hidden)."):format(name, slot))
            end
        end
    end
    if not next(self.pending) then self.waitingSlot, self.fullNotified = false, false end
    self.changed, self.added = changed, added
    self.lastError = nil
    self.lastStatus = self.waitingSlot and "Waiting for an empty action slot" or "Ready"
end

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        A:DB()
        A.ready = true
        A.baseline = false
        A:Request("login")
    elseif not A.ready then return
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" or event == "SPELLS_CHANGED" then
        A:Request("learn")
    elseif event == "PLAYER_REGEN_ENABLED" then A:Request("retry")
    elseif event == "ACTIONBAR_SLOT_CHANGED" and A.waitingSlot then A:Request("retry")
    elseif event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" or event == "UPDATE_SHAPESHIFT_FORM" then
        if next(A.pending) then A:Request("retry") end
    elseif event == "CURSOR_CHANGED" and A.waitingCursor then A:Request("retry")
    elseif event == "SPELL_TEXT_UPDATE" or event == "SPELL_DATA_LOAD_RESULT" then A:Request("retry") end
end)
frame:SetScript("OnUpdate", function(_, elapsed)
    if not A.ready or A.blocked or A.waitingSlot then return end
    if A.requested or A.wantUpgrade or A.waitingCursor or next(A.pending) then
        A.delay = (A.delay or 0) - elapsed
        if A.delay <= 0 then A.delay = 0.5 A:Process() end
    end
end)
for _, event in ipairs({"PLAYER_LOGIN", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED",
    "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED", "ACTIONBAR_SLOT_CHANGED", "SPELL_TEXT_UPDATE", "SPELL_DATA_LOAD_RESULT",
    "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM"}) do
    -- The legacy learn event is absent on some modern clients.
    pcall(frame.RegisterEvent, frame, event)
end

SLASH_DWDRANKUPFOREVER1 = "/dwdrank"
SlashCmdList.DWDRANKUPFOREVER = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    local db = A:DB()
    if command == "on" or command == "enable" then
        db.enabled = true A.baseline = false A.pending = {} A.blocked = nil A:Request("login") say("Enabled.")
    elseif command == "off" or command == "disable" then
        db.enabled = false A.pending = {} A.manual = false A.wantUpgrade = false A.blocked = nil A:Request("sync") say("Disabled.")
    elseif command:match("^add") then
        local value = command:match("^add%s+(%a+)$")
        if value == "on" or value == "enable" then db.addNew = true
        elseif value == "off" or value == "disable" then db.addNew = false A.pending = {} A.waitingSlot = false
        else db.addNew = not db.addNew if not db.addNew then A.pending = {} A.waitingSlot = false end end
        say("Auto-place newly learned abilities: " .. (db.addNew and "ON" or "OFF") .. ".")
    elseif command == "update" or command == "now" or command == "scan" or command == "fix" or command == "rescan" then
        -- Manual update only upgrades ranks. It never creates new add jobs.
        A:Request("manual") say("Checking spell ranks; cursor must be empty and combat must be over.")
    elseif command:match("^place%s+") then
        if not db.enabled then say("Enable RankUp first with /dwdrank on.") return end
        local query = command:match("^place%s+(.+)$")
        local book = A:BuildBook()
        if not book then say("Spellbook is not ready; try /dwdrank place again shortly.") return end
        for name, entry in pairs(book) do
            if name:lower() == query and not entry.passive then
                if not inCombat() and A:OnBars(name, true) then say(name .. " is already on a visible action button.") return end
                A.pending[name] = "manual" A.blocked = nil A.lastError = nil A:Request("retry")
                say("Placing " .. name .. " on an empty visible button when out of combat with an empty cursor.") return
            end
        end
        say("No learned active ability named '" .. query .. "' found.")
    elseif command == "visible" then
        db.placement = "visible" A:Request("retry") say("New abilities use empty visible action buttons, following stance/bar paging.")
    elseif command:match("^slots ") then
        local first, last = command:match("^slots%s+(%d+)%s+(%d+)$")
        first, last = tonumber(first), tonumber(last)
        if first and last and first >= 1 and last >= first and last <= MAX_SLOTS then
            db.firstSlot, db.lastSlot, db.placement = first, last, "range" A:Request("retry")
            say(("New abilities use empty slots %d-%d."):format(first, last))
        else say("Usage: /dwdrank slots FIRST LAST (1-120).") end
    elseif command == "debug" then db.debug = not db.debug say("Debug: " .. tostring(db.debug))
    elseif command == "status" then
        local count = 0 for _ in pairs(A.pending) do count = count + 1 end
        say(A.version .. "; enabled " .. tostring(db.enabled) .. ", add new " .. tostring(db.addNew)
            .. ", pending " .. count .. "; " .. (A.lastError or A.lastStatus or "Waiting for spellbook"))
        say("Spellbook: " .. (A.api or "not ready") .. "; placement " .. db.placement
            .. (db.placement == "range" and (" " .. db.firstSlot .. "-" .. db.lastSlot) or ("; visible buttons " .. #A:VisibleSlots())))
    else
        say("/dwdrank on | off | update | add on | add off | visible | slots FIRST LAST | place SPELL NAME | status")
        say("New abilities are added only after learning them. Login/manual scans do not fill your bars with existing spells.")
    end
end
