-- Forever returns first name + surname, not name + realm.
-- This shared, idempotent helper is bundled with each DWD addon so each can
-- also run independently. Never replace Blizzard's global name functions.
if DWD_ForeverIdentity then return end
local I = {}
DWD_ForeverIdentity = I
local function canonical(realm)
  return tostring(realm or "Unknown"):gsub("[%s%-']", "")
end
function I.Get(unit)
  unit = unit or "player"
  local first, second
  if type(UnitFullName) == "function" then first, second = UnitFullName(unit) end
  if not first and type(UnitName) == "function" then first, second = UnitName(unit) end
  local realm = type(GetRealmName) == "function" and GetRealmName() or nil
  local full = type(GetUnitName) == "function" and GetUnitName(unit, false) or nil
  if not full or full == "" then
    full = first
    if full and second and second ~= "" and not full:find(" ", 1, true)
      and canonical(second) ~= canonical(realm) then
      full = full .. " " .. second
    end
  end
  return full, realm
end
function I.Key(normalized)
  local name, realm = I.Get("player")
  return tostring(name or "Unknown") .. " - "
    .. (normalized and canonical(realm) or tostring(realm or "Unknown"))
end
function I.Adopt(map, key, reverse)
  if type(map) ~= "table" then return end
  if map[key] ~= nil then return map[key] end
  local first, second
  if type(UnitFullName) == "function" then first, second = UnitFullName("player") end
  local full, realm = I.Get("player")
  -- Only exact aliases of the current character are eligible for migration.
  -- Never guess from a first name shared by multiple surnames.
  local aliases = {}
  local function add(name, server)
    if not name or not server then return end
    if reverse then
      aliases[#aliases+1] = canonical(server) .. "-" .. name
      aliases[#aliases+1] = server .. "-" .. name
    else
      aliases[#aliases+1] = name .. " - " .. canonical(server)
      aliases[#aliases+1] = name .. " - " .. server
    end
  end
  add(full, realm)
  add(first, second)
  for _, alias in ipairs(aliases) do
    if map[alias] ~= nil then map[key] = map[alias]; return map[key] end
  end
end
