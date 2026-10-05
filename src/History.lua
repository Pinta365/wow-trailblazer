local _, TB = ...

-- Every character's travel lives in the account file, under TrailblazerDB.chars[guid]:
--   { name = "First", surname = "Last", race = "NightElf", sex = "f", class = "DRUID",
--     eras = { { since = date, race, sex, class }, ... },
--     lifetime = ledger, days = { [date] = record }, months = { [month] = record },
--     milestones = { ... } }
-- Characters are keyed by GUID, which survives name, race and appearance changes. Forever
-- has no realms to rely on; first name plus surname is unique across the region. `eras`
-- lists each race/sex/class the character has had and since when.
-- A record is { steps, jumps, yards = { [mode] = yd } }, plus flights, spent (copper)
-- and mountJumps once any happened. "All characters" is summed on demand. Days are kept
-- for about 13 months; months are kept for good so year views reach back.
local History = {}
TB.History = History

local KEEP_DAYS = 400

-- date() allocates a string, so look the day up at most once a minute.
local dayKey, monthKey, checkedAt = nil, nil, -math.huge

function History.Today()
  local now = GetTime()
  if now - checkedAt > 60 then
    dayKey = date("%Y-%m-%d")
    monthKey = dayKey:sub(1, 7)
    checkedAt = now
  end
  return dayKey, monthKey
end

local function blank()
  return { steps = 0, jumps = 0, yards = {} }
end

local function entry(book, key)
  local r = book[key]
  if not r then
    r = blank()
    book[key] = r
  end
  return r
end

-- Called several times a second while moving, so no temporary tables here.
local function addTravel(r, mode, yards, steps)
  r.steps = r.steps + steps
  r.yards[mode] = (r.yards[mode] or 0) + yards
end

function History.Record(mode, yards, steps)
  local day, month = History.Today()
  addTravel(entry(TB.char.days, day), mode, yards, steps)
  addTravel(entry(TB.char.months, month), mode, yards, steps)
end

function History.Jump(mounted)
  local day, month = History.Today()
  local d, m = entry(TB.char.days, day), entry(TB.char.months, month)
  if mounted then
    d.mountJumps, m.mountJumps = (d.mountJumps or 0) + 1, (m.mountJumps or 0) + 1
  else
    d.jumps, m.jumps = d.jumps + 1, m.jumps + 1
  end
end

function History.Flight(cost)
  local day, month = History.Today()
  for _, r in ipairs({ entry(TB.char.days, day), entry(TB.char.months, month) }) do
    r.flights = (r.flights or 0) + 1
    r.spent = (r.spent or 0) + cost
  end
end

function History.StepsToday()
  local r = TB.char.days[(History.Today())]
  return r and r.steps or 0
end

-- Yards travelled today by every means.
function History.DistanceToday()
  local r = TB.char.days[(History.Today())]
  local sum = 0
  if r then
    for _, yards in pairs(r.yards) do sum = sum + yards end
  end
  return sum
end

local function addRecord(into, r)
  into.steps = into.steps + r.steps
  into.jumps = into.jumps + r.jumps
  for mode, yards in pairs(r.yards) do into.yards[mode] = (into.yards[mode] or 0) + yards end
  if r.flights then
    into.flights = (into.flights or 0) + r.flights
    into.spent = (into.spent or 0) + r.spent
  end
  if r.mountJumps then into.mountJumps = (into.mountJumps or 0) + r.mountJumps end
end

-- The record for a day ("days") or month ("months") key: this character's own, or a new
-- table summing every character for scope "account". nil when nothing was recorded.
-- scope is "char" (current character), "account", or a character GUID.
-- `into` (optional) is a table to reuse for the account sum, so redraws that look up the
-- same keys again and again don't make new tables each time.
function History.Lookup(scope, kind, key, into)
  if scope ~= "account" then
    local char = scope == "char" and TB.char or TB.db.chars[scope]
    return char and char[kind][key]
  end
  local sum
  for _, char in pairs(TB.db.chars) do
    local r = char[kind][key]
    if r then
      if not sum then
        sum = into or blank()
        sum.steps, sum.jumps, sum.flights, sum.spent, sum.mountJumps = 0, 0, nil, nil, nil
        sum.yards = sum.yards or {}
        wipe(sum.yards)
      end
      addRecord(sum, r)
    end
  end
  return sum
end

local isSecret = issecretvalue or function() return false end

-- Refresh name, race, sex and class; open a new era when any of them changed. Identity can
-- be secret in restricted contexts, so only readable values are taken.
function History.Describe()
  local char = TB.char
  local name, surname = UnitName("player")
  char.name = name
  char.surname = surname ~= "" and surname or nil
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  local sex = UnitSex("player")
  if race and not isSecret(race) then char.race = race end
  if class and not isSecret(class) then char.class = class end
  if sex and not isSecret(sex) then char.sex = sex == 3 and "f" or "m" end

  char.eras = char.eras or {}
  local last = char.eras[#char.eras]
  if not last or last.race ~= char.race or last.sex ~= char.sex or last.class ~= char.class then
    char.eras[#char.eras + 1] = {
      since = (History.Today()), race = char.race, sex = char.sex, class = char.class,
    }
  end
end

local function trim(days)
  local keys = {}
  for k in pairs(days) do keys[#keys + 1] = k end
  if #keys <= KEEP_DAYS then return end
  table.sort(keys)
  for i = 1, #keys - KEEP_DAYS do days[keys[i]] = nil end
end

function History.Init()
  TB.db.chars = TB.db.chars or {}
  local guid = UnitGUID("player")
  local char = TB.db.chars[guid]
  if not char then
    char = { lifetime = TB.NewLedger(), days = {}, months = {} }
    TB.db.chars[guid] = char
  end
  -- The lifetime ledger needs every total, including any added after this character was
  -- first seen.
  local template, lifetime = TB.NewLedger(), char.lifetime
  for k, v in pairs(template) do
    if type(v) == "number" and lifetime[k] == nil then lifetime[k] = v end
  end
  for _, mode in ipairs(TB.MODES) do lifetime.yards[mode] = lifetime.yards[mode] or 0 end
  TB.char = char
  History.Describe()
  trim(char.days)
end

function History.ForgetCharacter()
  TB.char.lifetime, TB.char.days, TB.char.months = TB.NewLedger(), {}, {}
end
