local ADDON, TB = ...

-- Every yard travelled lands in exactly one of these modes. Only "foot" produces steps.
TB.MODES = { "foot", "mount", "shapeshift", "swim", "air", "vehicle", "taxi", "transport", "ghost" }
TB.MODE_LABEL = {
  foot    = "On foot",
  mount   = "Mounted",
  shapeshift = "Shapeshifted",
  swim    = "Swimming",
  air     = "Jumping / falling",
  vehicle = "Vehicles",
  taxi    = "Flight paths",
  transport = "Transports",
  ghost   = "As a ghost",
}

-- On-foot and swimming travel are further split by how the character moves.
TB.GAITS = { "run", "walk", "back", "walkBack", "strafe" }
TB.SWIM_STYLES = { "swimAhead", "swimBack", "swimSide" }
TB.STYLES_OF = { foot = TB.GAITS, swim = TB.SWIM_STYLES }
TB.GAIT_LABEL = {
  run = "Running", walk = "Walking", back = "Backpedaling", walkBack = "Walking backward",
  strafe = "Strafing",
  swimAhead = "Swimming forward", swimBack = "Swimming backward", swimSide = "Swimming sideways",
}

local accountDefaults = {
  shown   = true,
  locked  = false,
  units   = "km",
  debug   = false,
  anchor  = { point = "CENTER", x = 0, y = -180 },
  strides = {},   -- ["Race:sex"][gait] = { sum, runs } from calibration
}

function TB.NewLedger()
  local ledger = { steps = 0, jumps = 0, mountJumps = 0, guessed = 0, flights = 0, spent = 0,
    yards = {}, gaitYards = {}, gaitSteps = {} }
  for _, mode in ipairs(TB.MODES) do ledger.yards[mode] = 0 end
  for _, styles in pairs(TB.STYLES_OF) do
    for _, gait in ipairs(styles) do
      ledger.gaitYards[gait], ledger.gaitSteps[gait] = 0, 0
    end
  end
  return ledger
end

local function fillMissing(target, template)
  for k, v in pairs(template) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then target[k] = {} end
      fillMissing(target[k], v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
end

local function addTo(ledger, mode, gait, yards, steps, guessed)
  ledger.yards[mode] = ledger.yards[mode] + yards
  ledger.steps = ledger.steps + steps
  if gait then
    ledger.gaitYards[gait] = ledger.gaitYards[gait] + yards
    ledger.gaitSteps[gait] = ledger.gaitSteps[gait] + steps
  end
  if guessed then ledger.guessed = ledger.guessed + yards end
end

-- Single entry point for the motion engine. `gait` is set for on-foot travel only;
-- `guessed` marks yards that were inferred (no position or speed readable).
function TB.Log(mode, gait, yards, steps, guessed)
  addTo(TB.char.lifetime, mode, gait, yards, steps, guessed)
  addTo(TB.session, mode, gait, yards, steps, guessed)
  TB.History.Record(mode, yards, steps)
  TB.Milestones.Changed()
end

-- A jump from solid ground; jumps on a mount are counted apart.
function TB.LogJump(mounted)
  local field = mounted and "mountJumps" or "jumps"
  TB.char.lifetime[field] = TB.char.lifetime[field] + 1
  TB.session[field] = TB.session[field] + 1
  TB.History.Jump(mounted)
  TB.Milestones.Changed()
  TB.Panel.Refresh()
end

-- A flight path taken, and what it cost in copper.
function TB.LogFlight(cost)
  for _, ledger in ipairs({ TB.char.lifetime, TB.session }) do
    ledger.flights = ledger.flights + 1
    ledger.spent = ledger.spent + cost
  end
  TB.History.Flight(cost)
  TB.Milestones.Changed()
  TB.Panel.Refresh()
end

-- Formatting. Distances are kept in yards (the game's unit) and shown in km or miles.
local YARD_METRES = 0.9144

function TB.Grouped(n)
  local s = tostring(math.floor(n + 0.5))
  local head, tail = s:match("^(%-?%d)(%d*)$")
  return head .. tail:reverse():gsub("(%d%d%d)", "%1,"):reverse()
end

function TB.YardsPerUnit()
  return TB.db.units == "mi" and 1760 or 1000 / YARD_METRES
end

-- Short distances read in the smaller everyday unit: metres under 1 km, feet under 0.1 mi.
local SHORT_KM, SHORT_MI = 1000 / YARD_METRES, 176  -- yards

-- The small-unit text ("420 m", "350 ft") for a short distance, or nil.
function TB.ShortDistance(yards)
  if TB.db.units == "mi" then
    if yards < SHORT_MI then return ("%s ft"):format(TB.Grouped(yards * 3)) end
  elseif yards < SHORT_KM then
    return ("%s m"):format(TB.Grouped(yards * YARD_METRES))
  end
end

function TB.Distance(yards)
  local short = TB.ShortDistance(yards)
  if short then return short end
  if TB.db.units == "mi" then
    return ("%.2f mi"):format(yards / 1760)
  end
  return ("%.2f km"):format(yards * YARD_METRES / 1000)
end

function TB.Money(copper)
  return C_CurrencyInfo.GetCoinTextureString(copper)
end

-- "3 flights · 4s 20c" (with coin icons).
function TB.FlightsText(flights, spent)
  return ("%d flight%s  ·  %s"):format(flights, flights == 1 and "" or "s", TB.Money(spent))
end

function TB.Say(msg, ...)
  print("|cff7fd1b9Trailblazer|r " .. msg:format(...))
end

-- Saved files only need hundredths; full float precision just bloats them. Runs as the
-- game is about to write SavedVariables, so in-session counting keeps full precision.
local function tidy(t)
  for k, v in pairs(t) do
    if type(v) == "table" then
      tidy(v)
    elseif type(v) == "number" and v % 1 ~= 0 then
      t[k] = math.floor(v * 100 + 0.5) / 100
    end
  end
end

local saver = CreateFrame("Frame")
saver:RegisterEvent("PLAYER_LOGOUT")
saver:SetScript("OnEvent", function()
  if TrailblazerDB then tidy(TrailblazerDB) end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name == ADDON then
    TrailblazerDB = TrailblazerDB or {}
    fillMissing(TrailblazerDB, accountDefaults)
    TB.db = TrailblazerDB
    TB.session = TB.NewLedger()
  elseif event == "PLAYER_LOGIN" then
    TB.History.Init()

    TB.Strides.ResolveBody()
    TB.Motion.Start()
    TB.Panel.Build()
    TB.Milestones.Start()
    TB.Options.Register()
    self:UnregisterAllEvents()
  end
end)
