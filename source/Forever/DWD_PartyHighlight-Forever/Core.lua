local ADDON, A = ...
A.version = "2.0.0-forever.1"
A.media = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
A.overlays = setmetatable({}, {__mode = "k"})
A.status = {}
A.arrows = {"arrow_pointed", "arrow_chevron", "arrow_diamond", "arrow_triangle", "arrow_neon"}
A.styles = {"Corners", "Brackets", "Frame", "Diamond", "Chevron", "None"}
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local defaults = {
    enabled = true,
    colors = {{1, 0.25, 0.22}, {1, 0.6, 0.12}, {1, 0.9, 0.15}, {0.25, 1, 0.45}},
    labels = {"", "", "", ""},
    targets = {enabled = true, arrow = true, arrowType = "arrow_pointed", size = 24,
        offsetX = 0, offsetY = 16, spacing = 12, text = true, template = "P{slot}",
        fontSize = 11, textY = -1, glow = true, glowAlpha = 0.22, pulse = true},
    friends = {enabled = true, style = "Corners", colorMode = "Custom", color = {0.12, 0.95, 0.75},
        width = 150, height = 22, thickness = 2, padding = 5, offsetX = 0, offsetY = 0,
        alpha = 1, pulse = false, text = true, template = "PARTY {slot}",
        fontSize = 12, textX = 0, textY = 8},
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

local function merge(db, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            merge(db[k], v)
        elseif type(db[k]) ~= type(v) then db[k] = v end
    end
end

local function clamp(value, low, high, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return math.max(low, math.min(high, value))
end

local function contains(list, value)
    for _, item in ipairs(list) do if item == value then return true end end
end

local function text(value)
    -- Labels are plain text, not clickable links, color escapes, or textures.
    return type(value) == "string" and value:gsub("|", ""):gsub("[\r\n\t]", " ") or ""
end
A.CleanText = text

function A:DB()
    if type(DWD_PartyHighlightForeverDB) ~= "table" then DWD_PartyHighlightForeverDB = {} end
    local db = DWD_PartyHighlightForeverDB
    merge(db, defaults)
    local t, f = db.targets, db.friends
    t.size = clamp(t.size, 10, 64, 24)
    t.offsetX = clamp(t.offsetX, -150, 150, 0)
    t.offsetY = clamp(t.offsetY, -80, 120, 16)
    t.spacing = clamp(t.spacing, 0, 40, 12)
    t.fontSize = clamp(t.fontSize, 8, 30, 11)
    t.textY = clamp(t.textY, -60, 60, -1)
    t.glowAlpha = clamp(t.glowAlpha, 0, 1, 0.22)
    if not contains(self.arrows, t.arrowType) then t.arrowType = "arrow_pointed" end
    if not contains(self.styles, f.style) then f.style = "Corners" end
    if not contains({"Custom", "Party slot", "Class"}, f.colorMode) then f.colorMode = "Custom" end
    f.width = clamp(f.width, 50, 350, 150)
    f.height = clamp(f.height, 10, 100, 22)
    f.thickness = clamp(f.thickness, 1, 6, 2)
    f.padding = clamp(f.padding, 0, 25, 5)
    f.offsetX = clamp(f.offsetX, -150, 150, 0)
    f.offsetY = clamp(f.offsetY, -100, 100, 0)
    f.alpha = clamp(f.alpha, 0.1, 1, 1)
    f.fontSize = clamp(f.fontSize, 8, 30, 12)
    f.textX = clamp(f.textX, -150, 150, 0)
    f.textY = clamp(f.textY, -80, 100, 8)
    for i = 1, 4 do
        db.labels[i] = text(db.labels[i])
        for j = 1, 3 do db.colors[i][j] = clamp(db.colors[i][j], 0, 1, defaults.colors[i][j]) end
    end
    for j = 1, 3 do f.color[j] = clamp(f.color[j], 0, 1, defaults.friends.color[j]) end
    t.template, f.template = text(t.template), text(f.template)
    return db
end

function A:Reset()
    -- In-place reset keeps references held by an existing DWD profile valid.
    local db = self:DB()
    for k in pairs(db) do db[k] = nil end
    merge(db, defaults)
    self:Refresh()
end

local function secret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if not ok or secret(value) then return end
    return value
end
A.Read = read

local function usable(region)
    if secret(region) then return false end
    if not region or (type(region) ~= "table" and type(region) ~= "userdata") then return false end
    if type(region.IsForbidden) == "function" then
        local forbidden = read(region.IsForbidden, region)
        if forbidden ~= false then return false end
    end
    return true
end

local function getPlate(unit)
    if secret(unit) or type(unit) ~= "string" then return end
    local plate = C_NamePlate and read(C_NamePlate.GetNamePlateForUnit, unit)
    if usable(plate) then return plate end
end

local function guid(unit)
    local value = read(UnitGUID, unit)
    if type(value) == "string" and value ~= "" then return value end
end

function A:MemberName(unit, index)
    local full = read(GetUnitName, unit, false)
    if type(full) == "string" and full ~= "" then return full end
    if type(UnitFullName) == "function" then
        local ok, first, surname = pcall(UnitFullName, unit)
        if ok and not secret(first) and type(first) == "string" then
            if not secret(surname) and type(surname) == "string" and surname ~= "" then
                return first .. " " .. surname
            end
            return first
        end
    end
    return "Party " .. index
end

function A:Label(template, member)
    local values = {name = member.name, slot = tostring(member.index), role = member.role or "PARTY"}
    -- Callback replacement keeps '%' in character names and labels literal.
    local result = text(template):gsub("{(%a+)}", function(key) return values[key] or ("{" .. key .. "}") end)
    return result
end

local function animation(frame)
    local group = frame:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.45)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.6)
    group:SetLooping("BOUNCE")
    return group
end

local function pulse(frame, enabled, alpha)
    if enabled then
        frame:SetAlpha(alpha or 1)
        if not frame.animation:IsPlaying() then frame.animation:Play() end
    else
        if frame.animation:IsPlaying() then frame.animation:Stop() end
        frame:SetAlpha(alpha or 1)
    end
end

local function hide(frame)
    if not frame then return end
    if frame.animation and frame.animation:IsPlaying() then frame.animation:Stop() end
    frame:Hide()
end

local function overlay(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, 1)
    f:EnableMouse(false)
    f.animation = animation(f)
    f:Hide()
    return f
end

function A:CreateVisuals(parent)
    local visuals = {targets = overlay(parent), friend = overlay(parent)}
    local t, f = visuals.targets, visuals.friend
    t.markers = {}
    t.glow = t:CreateTexture(nil, "BACKGROUND")
    t.glow:SetTexture(WHITE)
    t.glow:SetBlendMode("ADD")
    for i = 1, 4 do
        local m = CreateFrame("Frame", nil, t)
        m:SetSize(1, 1)
        m:EnableMouse(false)
        m.arrow = m:CreateTexture(nil, "OVERLAY")
        m.label = m:CreateFontString(nil, "OVERLAY")
        m:Hide()
        t.markers[i] = m
    end
    f.lines = {}
    for i = 1, 8 do
        local line = f:CreateTexture(nil, "OVERLAY")
        line:SetTexture(WHITE)
        f.lines[i] = line
    end
    f.label = f:CreateFontString(nil, "OVERLAY")
    return visuals
end

local function anchorFor(plate)
    -- Only read existing regions. Never recolor, resize, reparent or hide them.
    local unitFrame = plate.unitFrame or plate.UnitFrame
    if usable(unitFrame) then
        local bar = unitFrame.healthBar or unitFrame.HealthBar
            or unitFrame.HealthBarsContainer
        if usable(bar) and read(bar.IsVisible or bar.IsShown, bar) then return bar, false end
        local name = unitFrame.name or unitFrame.Name or unitFrame.unitName
        if usable(name) and read(name.IsVisible or name.IsShown, name) then return name, false end
        if read(unitFrame.IsVisible or unitFrame.IsShown, unitFrame) then return unitFrame, false end
    end
    return plate, true
end

local function place(f, plate, anchor, top)
    f:ClearAllPoints()
    f:SetPoint("CENTER", anchor, top and "TOP" or "CENTER", 0, 0)
    local level = read(plate.GetFrameLevel, plate)
    local anchorLevel = read(anchor.GetFrameLevel, anchor)
    if type(level) ~= "number" then level = 1 end
    if type(anchorLevel) == "number" then level = math.max(level, anchorLevel) end
    local strata = read(anchor.GetFrameStrata, anchor) or read(plate.GetFrameStrata, plate)
    if type(strata) == "string" then f:SetFrameStrata(strata) end
    f:SetFrameLevel(math.min(level + 12, 9999))
end

function A:RenderTargets(visuals, plate, members, db)
    local f, options = visuals.targets, db.targets
    if not db.enabled or not options.enabled or not members or #members == 0 then hide(f) return end
    local anchor, top = anchorFor(plate)
    place(f, plate, anchor, top)
    for i = 1, 4 do
        local m, member = f.markers[i], members[i]
        if member then
            local c = db.colors[member.index]
            m:ClearAllPoints()
            local x = (i - (#members + 1) / 2) * (options.size + options.spacing)
            m:SetPoint("BOTTOM", f, "TOP", x + options.offsetX, options.offsetY)
            m.arrow:ClearAllPoints()
            m.arrow:SetPoint("BOTTOM", m, "TOP", 0, 0)
            m.arrow:SetSize(options.size, options.size)
            m.arrow:SetTexture(self.media .. options.arrowType)
            m.arrow:SetVertexColor(c[1], c[2], c[3], 1)
            m.arrow:SetShown(options.arrow)
            m.label:ClearAllPoints()
            m.label:SetPoint("TOP", m, "BOTTOM", 0, options.textY)
            m.label:SetFont(FONT, options.fontSize, "OUTLINE")
            m.label:SetText(self:Label(options.template, member))
            m.label:SetTextColor(c[1], c[2], c[3], 1)
            m.label:SetShown(options.text)
            m:Show()
        else m:Hide() end
    end
    local c = db.colors[members[1].index]
    f.glow:ClearAllPoints()
    f.glow:SetPoint("CENTER", f, "CENTER", options.offsetX, 0)
    f.glow:SetSize(math.max(54, #members * 30), 18)
    f.glow:SetVertexColor(c[1], c[2], c[3], options.glowAlpha)
    f.glow:SetShown(options.glow)
    f:Show()
    pulse(f, options.pulse)
end

local function segment(region, f, x, y, w, h, rotation, c)
    region:ClearAllPoints()
    region:SetPoint("CENTER", f, "CENTER", x, y)
    region:SetSize(w, h)
    region:SetRotation(rotation or 0)
    region:SetVertexColor(c[1], c[2], c[3], 1)
    region:Show()
end

function A:RenderFriend(visuals, plate, member, db)
    local f, options = visuals.friend, db.friends
    if not db.enabled or not options.enabled or not member then hide(f) return end
    local anchor, top = anchorFor(plate)
    place(f, plate, anchor, top)
    f:ClearAllPoints()
    f:SetPoint("CENTER", anchor, top and "TOP" or "CENTER", options.offsetX, options.offsetY)
    local c = options.color
    if options.colorMode == "Party slot" then c = db.colors[member.index]
    elseif options.colorMode == "Class" and member.classColor then c = member.classColor end
    local w, h, t = options.width / 2 + options.padding, options.height / 2 + options.padding, options.thickness
    for _, line in ipairs(f.lines) do line:Hide() end
    if options.style == "Frame" then
        segment(f.lines[1], f, 0, h, w * 2, t, 0, c)
        segment(f.lines[2], f, 0, -h, w * 2, t, 0, c)
        segment(f.lines[3], f, -w, 0, t, h * 2, 0, c)
        segment(f.lines[4], f, w, 0, t, h * 2, 0, c)
    elseif options.style == "Corners" or options.style == "Brackets" then
        local length = math.min(w / 2, 16)
        if options.style == "Brackets" then
            segment(f.lines[1], f, -w, 0, t, h * 2, 0, c)
            segment(f.lines[2], f, w, 0, t, h * 2, 0, c)
            segment(f.lines[3], f, -w + length / 2, h, length, t, 0, c)
            segment(f.lines[4], f, -w + length / 2, -h, length, t, 0, c)
            segment(f.lines[5], f, w - length / 2, h, length, t, 0, c)
            segment(f.lines[6], f, w - length / 2, -h, length, t, 0, c)
        else
            for i, xy in ipairs({{-1, 1}, {1, 1}, {-1, -1}, {1, -1}}) do
                segment(f.lines[i * 2 - 1], f, xy[1] * (w - length / 2), xy[2] * h, length, t, 0, c)
                segment(f.lines[i * 2], f, xy[1] * w, xy[2] * (h - 4), t, 8, 0, c)
            end
        end
    elseif options.style == "Diamond" then
        -- A diamond on either side of the plate, leaving the health bar open.
        for side = 1, 2 do
            local x = (side == 1 and -1 or 1) * (w + 8)
            for j, pos in ipairs({{-4, 4, 1}, {4, 4, -1}, {-4, -4, -1}, {4, -4, 1}}) do
                segment(f.lines[(side - 1) * 4 + j], f, x + pos[1], pos[2], 12, t, pos[3] * math.pi / 4, c)
            end
        end
    elseif options.style == "Chevron" then
        segment(f.lines[1], f, -w - 4, 4, 13, t, -math.pi / 4, c)
        segment(f.lines[2], f, -w - 4, -4, 13, t, math.pi / 4, c)
        segment(f.lines[3], f, w + 4, 4, 13, t, math.pi / 4, c)
        segment(f.lines[4], f, w + 4, -4, 13, t, -math.pi / 4, c)
    end
    local template = db.labels[member.index] ~= "" and db.labels[member.index] or options.template
    f.label:ClearAllPoints()
    f.label:SetPoint("BOTTOM", f, "CENTER", options.textX, h + options.textY)
    f.label:SetFont(FONT, options.fontSize, "OUTLINE")
    f.label:SetText(self:Label(template, member))
    f.label:SetTextColor(c[1], c[2], c[3], 1)
    f.label:SetShown(options.text)
    f:Show()
    pulse(f, options.pulse, options.alpha)
end

local function addMember(map, key, member)
    if not key then return end
    local list = map[key]
    if not list then list = {} map[key] = list end
    list[#list + 1] = member
end

local function plateUnit(plate)
    local unit = plate.namePlateUnitToken
    if secret(unit) then return end
    if type(unit) == "string" then return unit end
    unit = read(plate.GetUnit, plate)
    if type(unit) == "string" then return unit end
    -- Older/custom frames can expose only a public unit token here.
    local uf = plate.unitFrame or plate.UnitFrame
    if usable(uf) then
        unit = uf.unit
        if secret(unit) then return end
        if type(unit) ~= "string" then unit = uf.unitToken end
        if not secret(unit) and type(unit) == "string" then return unit end
    end
end

function A:HideAll()
    for plate, visuals in pairs(self.overlays) do
        if usable(plate) then hide(visuals.targets) hide(visuals.friend) end
    end
end

function A:Refresh()
    local db = self:DB()
    local status = {party = 0, targets = 0, friends = 0, skipped = 0}
    self.status = status
    if self.RefreshPreview then self:RefreshPreview(db) end
    if not db.enabled then self:HideAll() return end
    local members, targetPlates, targetGuids, friendPlates, friendGuids = {}, {}, {}, {}, {}
    for i = 1, 4 do
        local unit = "party" .. i
        if read(UnitExists, unit) then
            local member = {index = i, unit = unit, name = self:MemberName(unit, i)}
            local role = read(UnitGroupRolesAssigned, unit)
            if type(role) == "string" and role ~= "NONE" then member.role = role end
            local class
            if type(UnitClass) == "function" then
                local ok, localized, token = pcall(UnitClass, unit)
                if ok and not secret(token) and type(token) == "string" then class = token end
            end
            local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if color then member.classColor = {color.r, color.g, color.b} end
            members[#members + 1] = member
            status.party = status.party + 1
            if db.targets.enabled then
                addMember(targetPlates, getPlate(unit .. "target"), member)
                addMember(targetGuids, guid(unit .. "target"), member)
            end
            if db.friends.enabled then
                local plate, id = getPlate(unit), guid(unit)
                if plate then friendPlates[plate] = member end
                if id then friendGuids[id] = member end
            end
        end
    end
    -- No party, no scan or polling work beyond checking party1..4.
    if #members == 0 then self:HideAll() return end
    local plates = C_NamePlate and read(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" then status.unavailable = true self:HideAll() return end
    local seen = {}
    for _, plate in ipairs(plates) do
        if usable(plate) then
            local targets, friend = targetPlates[plate], friendPlates[plate]
            if not targets or not friend then
                local unit = plateUnit(plate)
                if type(unit) == "string" then
                    local id = guid(unit)
                    if id then targets, friend = targets or targetGuids[id], friend or friendGuids[id]
                    else status.skipped = status.skipped + 1 end
                end
            end
            if targets or friend then
                local visuals = self.overlays[plate]
                if not visuals then visuals = self:CreateVisuals(plate) self.overlays[plate] = visuals end
                self:RenderTargets(visuals, plate, targets, db)
                self:RenderFriend(visuals, plate, friend, db)
                seen[plate] = true
                if targets then status.targets = status.targets + 1 end
                if friend then status.friends = status.friends + 1 end
            end
        else status.skipped = status.skipped + 1 end
    end
    -- Hide unused pooled plates after reconciling the whole visible set. Do
    -- not stop/restart animations on plates that remain highlighted.
    for plate, visuals in pairs(self.overlays) do
        if not seen[plate] and usable(plate) then hide(visuals.targets) hide(visuals.friend) end
    end
end

local events = CreateFrame("Frame")
A.events = events
local started, dirty, elapsed = false, false, 0
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
    "UNIT_TARGET", "UNIT_NAME_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "CVAR_UPDATE"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit == ADDON then A:DB() end
        return
    elseif event == "PLAYER_LOGIN" then started = true end
    if not started then return end
    if event == "UNIT_TARGET" or event == "UNIT_NAME_UPDATE" then
        if secret(unit) or type(unit) ~= "string" or not unit:match("^party[1-4]$") then return end
    end
    if event == "NAME_PLATE_UNIT_REMOVED" and not secret(unit) and type(unit) == "string" then
        -- The API can already return nil at removal; match our tracked plate's
        -- public token too. The following frame's refresh reconciles all pools.
        for plate, visuals in pairs(A.overlays) do
            if usable(plate) then
                local token = plateUnit(plate)
                if not secret(token) and token == unit then hide(visuals.targets) hide(visuals.friend) end
            end
        end
    end
    dirty = true
end)
events:SetScript("OnUpdate", function(_, dt)
    if not started then return end
    elapsed = elapsed + dt
    -- Coalesce event bursts. The fallback also handles target/nameplate updates
    -- delivered in a different order and reused Plater regions.
    if (dirty and elapsed >= 0.03) or elapsed >= 0.2 then
        dirty, elapsed = false, 0
        A:Refresh()
    end
end)

SLASH_DWDPARTYHIGHLIGHTFOREVER1 = "/dwdph"
SLASH_DWDPARTYHIGHLIGHTFOREVER2 = "/dwdpth"
SlashCmdList.DWDPARTYHIGHLIGHTFOREVER = function(message)
    local cmd = (message or ""):match("^%s*(.-)%s*$"):lower()
    if cmd == "refresh" then A:Refresh()
    elseif cmd == "status" then
        A:Refresh()
        local s = A.status
        print("|cff22efbbDWD Party Highlight:|r " .. A.version .. "; party " .. s.party
            .. ", target plates " .. s.targets .. ", party plates " .. s.friends .. ", skipped/restricted " .. s.skipped)
    elseif cmd == "on" or cmd == "off" then
        A:DB().enabled = cmd == "on"
        A:Refresh()
    else A:OpenOptions(cmd == "preview" and 1 or nil) end
end
