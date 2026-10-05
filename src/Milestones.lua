local _, TB = ...

-- Milestones: travel achievements in up to four tiers. The definitions live here; the
-- saved data only holds the date each tier was reached:
--   TrailblazerDB.milestones[id] = { [tier] = "2026-10-05" }         account milestones
--   TrailblazerDB.chars[guid].milestones[id] = { ... }               character milestones
-- A tier passed before milestones existed is stored as BEFORE_TRACKING instead of a date.
-- Progress is never stored; it is computed from the totals Trailblazer already keeps.
local Milestones = {}
TB.Milestones = Milestones

local KM = 1000 / 0.9144   -- yards
local M = KM / 1000
local GOLD = 10000         -- copper
local CHECK_EVERY = 1      -- seconds between checks while travel is being logged
local BEFORE_TRACKING = "-"

Milestones.TIERS = {
  { name = "Bronze",    points = 5,  color = { 0.80, 0.50, 0.20 } },
  { name = "Silver",    points = 10, color = { 0.78, 0.80, 0.85 } },
  { name = "Gold",      points = 25, color = { 1.00, 0.82, 0.00 } },
  { name = "Legendary", points = 50, color = { 1.00, 0.50, 0.00 } },
}

Milestones.CATEGORIES = {
  { id = "steps",    name = "Steps" },
  { id = "distance", name = "Distance" },
  { id = "swim",     name = "Swimming" },
  { id = "air",      name = "Jumping" },
  { id = "flight",   name = "Flight" },
  { id = "sea",      name = "Seafaring" },
  { id = "feats",    name = "Feats" },
  { id = "account",  name = "Account" },
}

-- Value helpers. Character milestones get the character; account milestones get nil.
local function yards(mode) return function(char) return char.lifetime.yards[mode] or 0 end end
local function gait(name) return function(char) return char.lifetime.gaitYards[name] or 0 end end
local function field(name) return function(char) return char.lifetime[name] or 0 end end

local function accountSum(perChar)
  return function()
    local sum = 0
    for _, char in pairs(TB.db.chars) do sum = sum + perChar(char) end
    return sum
  end
end

-- The best single day for a record field ("steps", "jumps") or a mode's yards.
local function bestDay(get)
  return function(char)
    local best = 0
    for _, r in pairs(char.days) do
      local v = get(r)
      if v > best then best = v end
    end
    return best
  end
end
local function daySteps(r) return r.steps end
local function dayJumps(r) return r.jumps end
local function dayFoot(r) return r.yards.foot or 0 end

local function activeDays(char)
  local n = 0
  for _, r in pairs(char.days) do
    if r.steps >= 1000 then n = n + 1 end
  end
  return n
end

-- Characters with at least 10 km on foot; `by` counts distinct values of that field.
local WALKED = 10 * KM
local seen = {}
local function walkers(by)
  return function()
    wipe(seen)
    local n = 0
    for _, char in pairs(TB.db.chars) do
      local key = by and char[by] or char
      if key and (char.lifetime.yards.foot or 0) >= WALKED and not seen[key] then
        seen[key] = true
        n = n + 1
      end
    end
    return n
  end
end

-- Tiers at Gold or above across every character and the account, this milestone aside.
local function goldTiers()
  local n = 0
  local function count(store)
    for id, got in pairs(store or {}) do
      if id ~= "completionist" then
        if got[3] then n = n + 1 end
        if got[4] then n = n + 1 end
      end
    end
  end
  count(TB.db.milestones)
  for _, char in pairs(TB.db.chars) do count(char.milestones) end
  return n
end

-- unit: how values and goals are shown ("count", "distance" in yards, "money" in copper).
-- goals[tier] = target; a missing tier is skipped (Marathon is a single Gold tier).
Milestones.LIST = {
  -- Steps
  { id = "steps", cat = "steps", scope = "char", unit = "count", icon = "INV_Boots_01",
    name = "One Foot in Front of the Other", text = "Lifetime steps.",
    goals = { 10000, 100000, 500000, 1000000 }, value = field("steps") },
  { id = "bestDaySteps", cat = "steps", scope = "char", unit = "count", icon = "Ability_Rogue_Sprint",
    name = "Best Foot Forward", text = "Steps in a single day.",
    goals = { 5000, 10000, 20000, 40000 }, value = bestDay(daySteps) },
  { id = "activeDays", cat = "steps", scope = "char", unit = "count", icon = "INV_Misc_PocketWatch_01",
    name = "Daily Constitutional", text = "Days with at least 1,000 steps.",
    goals = { 7, 30, 100, 365 }, value = activeDays },
  { id = "accountSteps", cat = "steps", scope = "account", unit = "count", icon = "Ability_Tracking",
    name = "Thousand-League Boots", text = "Steps across all characters.",
    goals = { 100000, 1000000, 5000000, 10000000 }, value = accountSum(field("steps")) },

  -- Distance on foot
  { id = "foot", cat = "distance", scope = "char", unit = "distance", icon = "inv_misc_map02",
    name = "Trailblazer", text = "Lifetime distance on foot.",
    goals = { 10 * KM, 100 * KM, 500 * KM, 1000 * KM }, value = yards("foot") },
  { id = "marathon", cat = "distance", scope = "char", unit = "distance", icon = "Spell_Nature_Swiftness",
    name = "Marathon", text = "Walk a marathon's worth on foot in total.",
    goals = { nil, nil, 42.195 * KM }, value = yards("foot") },
  { id = "bestDayFoot", cat = "distance", scope = "char", unit = "distance", icon = "icon_treasuremap",
    name = "Day Tripper", text = "On foot in a single day.",
    goals = { 5 * KM, 10 * KM, 21.0975 * KM, 42.195 * KM }, value = bestDay(dayFoot) },
  { id = "ghost", cat = "distance", scope = "char", unit = "distance", icon = "Spell_Holy_SealOfSacrifice",
    name = "Corpse Run", text = "Distance travelled as a ghost.",
    goals = { 1 * KM, 10 * KM, 50 * KM, 100 * KM }, value = yards("ghost") },
  { id = "shapeshift", cat = "distance", scope = "char", unit = "distance", icon = "Ability_Tracking",
    name = "Shapeshifter", text = "Distance travelled in an animal form.",
    goals = { 10 * KM, 100 * KM, 500 * KM, 1000 * KM }, value = yards("shapeshift") },
  { id = "accountFoot", cat = "distance", scope = "account", unit = "distance", icon = "Ability_Tracking",
    name = "Pilgrim", text = "On foot across all characters.",
    goals = { 100 * KM, 1000 * KM, 5000 * KM, 10000 * KM }, value = accountSum(yards("foot")) },

  -- Swimming
  { id = "swim", cat = "swim", scope = "char", unit = "distance", icon = "Spell_Shadow_DemonBreath",
    name = "Fish Out of Water", text = "Lifetime distance swum.",
    goals = { 1 * KM, 10 * KM, 50 * KM, 100 * KM }, value = yards("swim") },
  { id = "backstroke", cat = "swim", scope = "char", unit = "distance", icon = "INV_Misc_Fish_02",
    name = "Backstroke", text = "Swimming backward.",
    goals = { 100 * M, 1 * KM, 5 * KM }, value = gait("swimBack") },
  { id = "sidestroke", cat = "swim", scope = "char", unit = "distance", icon = "INV_Misc_Fish_02",
    name = "Sidestroke", text = "Swimming sideways.",
    goals = { 100 * M, 1 * KM, 5 * KM }, value = gait("swimSide") },
  { id = "accountSwim", cat = "swim", scope = "account", unit = "distance", icon = "Spell_Frost_SummonWaterElemental",
    name = "Tidal Wave", text = "Distance swum across all characters.",
    goals = { 10 * KM, 100 * KM, 500 * KM, 1000 * KM }, value = accountSum(yards("swim")) },

  -- Jumping and falling
  { id = "jumps", cat = "air", scope = "char", unit = "count", icon = "Spell_Magic_FeatherFall",
    name = "Hop to It", text = "Lifetime jumps.",
    goals = { 100, 1000, 10000, 50000 }, value = field("jumps") },
  { id = "bestDayJumps", cat = "air", scope = "char", unit = "count", icon = "Spell_Magic_FeatherFall",
    name = "Bunny Hopper", text = "Jumps in a single day.",
    goals = { 100, 250, 500, 1000 }, value = bestDay(dayJumps) },
  { id = "air", cat = "air", scope = "char", unit = "distance", icon = "Spell_Magic_FeatherFall",
    name = "Leap of Faith", text = "Distance travelled jumping or falling.",
    goals = { 1 * KM, 5 * KM, 20 * KM }, value = yards("air") },
  { id = "mountJumps", cat = "air", scope = "char", unit = "count", icon = "INV_Horse3Saddle008_Chestnut",
    name = "Show Jumper", text = "Jumps while mounted.",
    goals = { 50, 500, 2500, 10000 }, value = field("mountJumps") },
  { id = "accountJumps", cat = "air", scope = "account", unit = "count", icon = "Spell_Magic_FeatherFall",
    name = "Spring in Every Step", text = "Jumps across all characters.",
    goals = { 1000, 10000, 100000, 500000 }, value = accountSum(field("jumps")) },

  -- Flight paths
  { id = "flights", cat = "flight", scope = "char", unit = "count", icon = "Ability_Hunter_EagleEye",
    name = "Frequent Flyer", text = "Flight paths taken.",
    goals = { 1, 25, 100, 500 }, value = field("flights") },
  { id = "taxi", cat = "flight", scope = "char", unit = "distance", icon = "Ability_Hunter_EagleEye",
    name = "Gryphon's Best Friend", text = "Distance flown on flight paths.",
    goals = { 100 * KM, 500 * KM, 2000 * KM, 5000 * KM }, value = yards("taxi") },
  { id = "fares", cat = "flight", scope = "char", unit = "money", icon = "inv_misc_coin_01",
    name = "Paying Customer", text = "Spent on flight fares.",
    goals = { 1 * GOLD, 10 * GOLD, 50 * GOLD, 100 * GOLD }, value = field("spent") },
  { id = "accountFlights", cat = "flight", scope = "account", unit = "count", icon = "Ability_Hunter_EagleEye",
    name = "Air Miles", text = "Flights across all characters.",
    goals = { 100, 500, 2000, 5000 }, value = accountSum(field("flights")) },
  { id = "accountFares", cat = "flight", scope = "account", unit = "money", icon = "INV_Misc_Coin_17",
    name = "Flight Master's Favourite", text = "Fares across all characters.",
    goals = { 10 * GOLD, 100 * GOLD, 500 * GOLD, 1000 * GOLD }, value = accountSum(field("spent")) },

  -- Seafaring
  { id = "transport", cat = "sea", scope = "char", unit = "distance", icon = "icon_treasuremap",
    name = "Sea Legs", text = "Distance carried by boats, zeppelins and trams.",
    goals = { 10 * KM, 100 * KM, 500 * KM, 1000 * KM }, value = yards("transport") },
  { id = "accountTransport", cat = "sea", scope = "account", unit = "distance", icon = "icon_treasuremap",
    name = "Admiral of the Fleet", text = "Carried by transports across all characters.",
    goals = { 100 * KM, 1000 * KM, 5000 * KM, 10000 * KM }, value = accountSum(yards("transport")) },

  -- Feats
  { id = "backpedal", cat = "feats", scope = "char", unit = "distance", icon = "Ability_Rogue_Sprint",
    name = "Moonwalker", text = "Distance backpedalling.",
    goals = { 500 * M, 5 * KM, 20 * KM, 50 * KM }, value = gait("back") },
  { id = "strafe", cat = "feats", scope = "char", unit = "distance", icon = "Ability_Rogue_Sprint",
    name = "Crab Walk", text = "Distance strafing.",
    goals = { 500 * M, 5 * KM, 20 * KM, 50 * KM }, value = gait("strafe") },
  { id = "walk", cat = "feats", scope = "char", unit = "distance", icon = "INV_Boots_01",
    name = "Leisurely Stroll", text = "Distance walking (walk mode on).",
    goals = { 1 * KM, 10 * KM, 50 * KM, 100 * KM }, value = gait("walk") },
  { id = "walkBack", cat = "feats", scope = "char", unit = "distance", icon = "INV_Boots_01",
    name = "Tactical Retreat", text = "Distance walking backward.",
    goals = { 100 * M, 1 * KM, 5 * KM }, value = gait("walkBack") },
  { id = "mount", cat = "feats", scope = "char", unit = "distance", icon = "INV_Horse3Saddle008_Chestnut",
    name = "Saddle Sore", text = "Distance mounted.",
    goals = { 100 * KM, 1000 * KM, 5000 * KM, 10000 * KM }, value = yards("mount") },
  { id = "vehicle", cat = "feats", scope = "char", unit = "distance", icon = "ACHIEVEMENT_GUILDPERK_MOUNTUP",
    name = "All Aboard", text = "Distance in vehicles.",
    goals = { 1 * KM, 10 * KM, 100 * KM }, value = yards("vehicle") },

  -- Account-wide
  { id = "fellowship", cat = "account", scope = "account", unit = "count", icon = "achievement_guildperk_everybodysfriend",
    name = "Fellowship of the Road", text = "Characters who have walked at least 10 km each.",
    goals = { 2, 5, 10, 20 }, value = walkers(nil) },
  { id = "races", cat = "account", scope = "account", unit = "count", icon = "Achievement_General_StayClassy",
    name = "Many Shoes", text = "Different races that have walked 10 km each.",
    goals = { 3, 6, 9 }, value = walkers("race") },
  { id = "classes", cat = "account", scope = "account", unit = "count", icon = "Ability_Racial_JackofAllTrades",
    name = "Jack of All Trades", text = "Different classes that have walked 10 km each.",
    goals = { 3, 6, 9 }, value = walkers("class") },
  { id = "completionist", cat = "account", scope = "account", unit = "count", icon = "Achievement_Quests_Completed_06",
    name = "Completionist", text = "Milestone tiers reached at Gold or above, on any character.",
    goals = { 10, 25, 50, 100 }, value = goldTiers },
}

function Milestones.Icon(m)
  return "Interface\\Icons\\" .. m.icon
end

-- The saved tiers for a milestone: { [tier] = date } (empty table if none reached).
local NONE = {}
function Milestones.Reached(m, char)
  local store = m.scope == "account" and TB.db.milestones or (char or TB.char).milestones
  return store and store[m.id] or NONE
end

function Milestones.Value(m, char)
  if m.scope == "account" then return m.value() end
  return m.value(char or TB.char)
end

-- The next tier still to reach and its goal, or nil when every tier is done.
function Milestones.NextTier(m, char)
  local got = Milestones.Reached(m, char)
  for tier = 1, 4 do
    if m.goals[tier] and not got[tier] then return tier, m.goals[tier] end
  end
end

-- Points earned and tiers reached, for one character's milestones or the account's.
function Milestones.Score(scope, char)
  local points, tiers, total = 0, 0, 0
  for _, m in ipairs(Milestones.LIST) do
    if m.scope == scope then
      local got = Milestones.Reached(m, char)
      for tier = 1, 4 do
        if m.goals[tier] then
          total = total + 1
          if got[tier] then
            tiers = tiers + 1
            points = points + Milestones.TIERS[tier].points
          end
        end
      end
    end
  end
  return points, tiers, total
end

-- "42.2 km", "500 m", "1,000", "10g": the way a goal or progress amount reads.
function Milestones.Format(m, amount)
  if m.unit == "distance" then
    local short = TB.ShortDistance(amount)
    if short then return short end
    local units = amount / TB.YardsPerUnit()
    local text = units >= 100 and TB.Grouped(units) or tostring(math.floor(units * 10 + 0.5) / 10)
    return ("%s %s"):format(text, TB.db.units)
  elseif m.unit == "money" then
    return TB.Money(amount)
  end
  return TB.Grouped(amount)
end

-- Ticks every newly passed tier. `quiet` stores them without toasts (first sight of a
-- character or account, whose history predates milestones).
local function check(quiet)
  local today = (TB.History.Today())
  for _, m in ipairs(Milestones.LIST) do
    local store = m.scope == "account" and TB.db.milestones or TB.char.milestones
    local got = store[m.id]
    local value = Milestones.Value(m)
    for tier = 1, 4 do
      local goal = m.goals[tier]
      if goal and value >= goal and not (got and got[tier]) then
        got = got or {}
        store[m.id] = got
        got[tier] = quiet and BEFORE_TRACKING or today
        if not quiet then TB.Toast.Show(m, tier) end
      end
    end
  end
end

local dirty = false

-- Called whenever travel is logged; the actual check runs at most once a second.
function Milestones.Changed()
  dirty = true
end

function Milestones.Start()
  -- First sight: tick what the history already passed, silently.
  local quietAccount, quietChar = TB.db.milestones == nil, TB.char.milestones == nil
  TB.db.milestones = TB.db.milestones or {}
  TB.char.milestones = TB.char.milestones or {}
  check(quietAccount or quietChar)
  C_Timer.NewTicker(CHECK_EVERY, function()
    if dirty then
      dirty = false
      check(false)
    end
  end)
end

function Milestones.WasBeforeTracking(date)
  return date == BEFORE_TRACKING
end
