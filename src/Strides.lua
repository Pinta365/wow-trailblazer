local _, TB = ...

-- Stride lengths (yards per footfall) by race, sex and gait: measured values ship with the
-- addon, and the player's own calibration takes precedence.
local Strides = {}
TB.Strides = Strides

Strides.PACES = { "run", "walk", "back", "walkBack" }

-- Measured yards per footfall, by upper-cased race file token, sex ("m"/"f") and gait.
-- Strafing has no stride of its own; it uses run or walk.
local MEASURED = {
  HUMAN = {
    m = { run = 2.33, walk = 1.25, back = 1.30 },
    f = { run = 2.33, walk = 1.25, back = 1.31 },
  },
  NIGHTELF = {
    m = { run = 2.32, walk = 1.24, back = 2.20 },
    f = { run = 2.27, walk = 1.15, back = 1.18 },
  },
  DWARF = {
    m = { run = 2.09, walk = 1.01, back = 1.81 },
    f = { run = 2.77, walk = 1.25, back = 2.25 },
  },
  GNOME = {
    m = { run = 2.22, walk = 0.61, back = 1.02 },
    f = { run = 2.15, walk = 0.61, back = 1.00 },
  },
  ORC = {
    m = { run = 2.34, walk = 1.37, back = 2.42 },
    f = { run = 2.35, walk = 1.18, back = 2.10 },
  },
  SCOURGE = {
    m = { run = 2.14, walk = 1.32, back = 1.36 },
    f = { run = 2.36, walk = 1.25, back = 2.25 },
  },
  TAUREN = {
    m = { run = 3.13, walk = 2.41, back = 3.22 },
    f = { run = 2.92, walk = 1.58, back = 2.25 },
  },
  TROLL = {
    m = { run = 2.79, walk = 1.66, back = 2.92 },
    f = { run = 2.27, walk = 1.30, back = 1.30 },
  },
  SKYBORNE = {
    m = { run = 2.32, walk = 1.22, back = 1.31 },
    f = { run = 2.33, walk = 1.15, back = 1.24 },
  },
}

-- For a race the table doesn't know: the average of all measured bodies per gait.
local FALLBACK = { run = 2.41, walk = 1.27, back = 1.80, walkBack = 1.27 }

-- Race/sex are secret while unit identity is restricted, so resolve once at login
-- and only overwrite with a readable value.
local body = { race = "Human", sex = 2 }

local isSecret = issecretvalue or function() return false end

function Strides.ResolveBody()
  local _, race = UnitRace("player")
  local sex = UnitSex("player")
  if race and not isSecret(race) then body.race = race end
  if sex and not isSecret(sex) then body.sex = sex end
end

function Strides.BodyKey()
  return body.race .. ":" .. (body.sex == 3 and "f" or "m")
end

-- Shipped stride for this body, and whether it was measured for it (vs. the fallback).
-- A measured walk stands in for an unmeasured walkBack.
function Strides.Estimate(gait)
  local race = MEASURED[body.race:upper()]
  local set = race and race[body.sex == 3 and "f" or "m"]
  if set then
    if set[gait] then return set[gait], true end
    if gait == "walkBack" and set.walk then return set.walk, true end
  end
  return FALLBACK[gait], false
end

-- Calibrations are kept as { sum = total of each run's stride, runs = count } so every
-- saved run adds to the average.
local function measured(gait)
  local saved = TB.db.strides[Strides.BodyKey()]
  return saved and saved[gait]
end

function Strides.Calibration(gait)
  local entry = measured(gait)
  if entry and entry.runs > 0 then return entry.sum / entry.runs, entry.runs end
end

-- Your own calibration first; your walk also stands in for an uncalibrated walkBack,
-- ahead of any built-in value.
function Strides.Length(gait)
  local own = Strides.Calibration(gait)
  if own then return own end
  if gait == "walkBack" then
    local _, builtIn = Strides.Estimate("walkBack")
    own = Strides.Calibration("walk")
    if own and not builtIn then return own end
  end
  return (Strides.Estimate(gait))
end

-- Adds one run's stride to the average and returns the new average and run count.
function Strides.Save(gait, yards)
  local key = Strides.BodyKey()
  TB.db.strides[key] = TB.db.strides[key] or {}
  local entry = measured(gait) or { sum = 0, runs = 0 }
  entry.sum, entry.runs = entry.sum + yards, entry.runs + 1
  TB.db.strides[key][gait] = entry
  return entry.sum / entry.runs, entry.runs
end

function Strides.Forget()
  TB.db.strides[Strides.BodyKey()] = nil
end
