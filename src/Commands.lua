local ADDON, TB = ...

-- Slash commands: /trailblazer (or /trail) followed by a subcommand; no subcommand toggles
-- the panel.

local function printLedger(title, ledger)
  TB.Say("%s: %s steps, %s jumps, %s mount jumps", title, TB.Grouped(ledger.steps),
    TB.Grouped(ledger.jumps), TB.Grouped(ledger.mountJumps))
  for _, mode in ipairs(TB.MODES) do
    if ledger.yards[mode] > 0 then
      print(("    %s: %s"):format(TB.MODE_LABEL[mode], TB.Distance(ledger.yards[mode])))
    end
    for _, gait in ipairs(TB.STYLES_OF[mode] or {}) do
      local yards = ledger.gaitYards[gait]
      if yards > 0 then
        local steps = mode == "foot" and (TB.Grouped(ledger.gaitSteps[gait]) .. " steps, ") or ""
        print(("        %s: %s%s"):format(TB.GAIT_LABEL[gait], steps, TB.Distance(yards)))
      end
    end
    if mode == "taxi" and ledger.flights > 0 then
      print("        Fares: " .. TB.FlightsText(ledger.flights, ledger.spent))
    end
  end
end

local function showStrides()
  TB.Say("Strides for %s (yards per footfall):", TB.Strides.BodyKey())
  for _, gait in ipairs(TB.Strides.PACES) do
    local _, runs = TB.Strides.Calibration(gait)
    local _, builtIn = TB.Strides.Estimate(gait)
    local source = runs and ("(your average of %d run%s)"):format(runs, runs == 1 and "" or "s")
      or builtIn and "(built-in for this race)"
      or "(fallback: no data for this race yet)"
    print(("    %s: %.2f %s"):format(gait, TB.Strides.Length(gait), source))
  end
end

-- /trailblazer calibrate opens the window; start, stop <footfalls> and clear still work typed.
local function calibrate(arg)
  local verb, count = arg:match("^(%S*)%s*(%S*)$")
  if verb == "start" then
    TB.Calib.Start()
    TB.Say("Calibrating. Move in ONE gait and count footfalls, then /trailblazer calibrate stop <footfalls>.")
  elseif verb == "stop" then
    local _, msg = TB.Calib.Finish(tonumber(count))
    TB.Say(msg)
  elseif verb == "clear" then
    TB.Strides.Forget()
    TB.Say("Calibration cleared for %s.", TB.Strides.BodyKey())
  else
    TB.Calib.Toggle()
  end
end

StaticPopupDialogs.TRAILBLAZER_WIPE = {
  text = "Erase all Trailblazer totals for this character?",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    TB.char.lifetime, TB.session = TB.NewLedger(), TB.NewLedger()
    TB.History.ForgetCharacter()
    TB.Panel.Refresh()
    TB.Say("All totals erased.")
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- The name of `value` in one of the game's Enum tables, e.g. Enum.GameMode.
local function enumName(enum, value)
  for name, v in pairs(enum or {}) do
    if v == value then return name end
  end
  return "?"
end

-- Prints how the game identifies this character, for comparing characters across Forever
-- game modes. Each call is guarded, since some of these may be missing or change.
local function whoami()
  local function try(fn, ...)
    if not fn then return "n/a" end
    local results = { pcall(fn, ...) }
    if not results[1] then return "error" end
    for i = 2, #results do results[i] = tostring(results[i]) end
    return table.concat(results, ", ", 2)
  end
  local rules = C_GameRules or {}
  TB.Say("Who am I")
  print("    Name: " .. try(UnitName, "player"))
  print("    GUID: " .. try(UnitGUID, "player"))
  print("    Realm: " .. try(GetRealmName))
  local mode = rules.GetActiveGameMode and select(2, pcall(rules.GetActiveGameMode))
  print(("    Game mode: %s (%s), record %s"):format(tostring(mode), enumName(Enum.GameMode, mode),
    try(rules.GetCurrentGameModeRecordID)))
  local preset = rules.GetForeverExperiencePreset and select(2, pcall(rules.GetForeverExperiencePreset))
  print(("    Experience preset: %s (%s)"):format(tostring(preset), enumName(Enum.ForeverExperiencePreset, preset)))
  print("    Project: " .. tostring(WOW_PROJECT_ID))
  local count = 0
  for _ in pairs(TB.db.chars) do count = count + 1 end
  print(("    Saved characters: %d"):format(count))
end

-- Memory now and 10 seconds later (the growth is garbage made while moving), plus the
-- addon profiler's CPU figures when it is enabled.
local PERF_WINDOW = 10
local function perf()
  UpdateAddOnMemoryUsage()
  local before = GetAddOnMemoryUsage(ADDON)
  TB.Say("Memory: %.0f KB. Measuring again in %d s; keep moving to see the garbage rate.",
    before, PERF_WINDOW)
  local profiler = C_AddOnProfiler
  if profiler and profiler.IsEnabled() then
    local m = Enum.AddOnProfilerMetric
    local function metric(which) return profiler.GetAddOnMetric(ADDON, which) end
    local share = metric(m.RecentAverageTime) / math.max(profiler.GetApplicationMetric(m.RecentAverageTime), 1e-9)
    print(("    CPU per frame: %.3f ms recent (%.2f%% of the game), %.3f ms session average, %.2f ms peak")
      :format(metric(m.RecentAverageTime), share * 100, metric(m.SessionAverageTime), metric(m.PeakTime)))
    print(("    Frames over 1 ms: %d, over 5 ms: %d"):format(metric(m.CountTimeOver1Ms), metric(m.CountTimeOver5Ms)))
  else
    print("    CPU: the addon profiler is off.")
  end
  C_Timer.After(PERF_WINDOW, function()
    UpdateAddOnMemoryUsage()
    local after = GetAddOnMemoryUsage(ADDON)
    TB.Say("Memory: %.0f KB, %+.1f KB/s over %d s.", after, (after - before) / PERF_WINDOW, PERF_WINDOW)
  end)
end

local handlers = {
  whoami = whoami,
  perf   = perf,
  show   = function() TB.Panel.SetShown(true) end,
  hide   = function() TB.Panel.SetShown(false) end,
  lock   = function() TB.db.locked = true;  TB.Say("Panel locked.") end,
  unlock = function() TB.db.locked = false; TB.Say("Panel unlocked; drag to move.") end,
  stats  = function()
    TB.Say("Today: %s steps", TB.Grouped(TB.History.StepsToday()))
    printLedger("Session", TB.session)
    printLedger("All time", TB.char.lifetime)
  end,
  units  = function(arg)
    local units = ({ km = "km", metric = "km", mi = "mi", imperial = "mi" })[arg]
    if units then
      TB.db.units = units
      TB.Panel.Refresh()
    end
    TB.Say("Units: %s", TB.db.units == "mi" and "imperial (mi, ft)" or "metric (km, m)")
  end,
  debug  = function()
    TB.db.debug = not TB.db.debug
    TB.Panel.Refresh()
    TB.Say("Debug readout %s.", TB.db.debug and "on" or "off")
  end,
  strides   = showStrides,
  history   = function() TB.HistoryPage.Toggle() end,
  milestones = function() TB.MilestonesPage.Toggle() end,
  options   = function() TB.Options.Open() end,
  calibrate = calibrate,
  reset  = function(arg)
    if arg == "all" then
      StaticPopup_Show("TRAILBLAZER_WIPE")
    else
      TB.session = TB.NewLedger()
      TB.Panel.Refresh()
      TB.Say("Session totals reset. (/trailblazer reset all erases everything)")
    end
  end,
}

SLASH_TRAILBLAZER1 = "/trailblazer"
SLASH_TRAILBLAZER2 = "/trail"
SlashCmdList.TRAILBLAZER = function(input)
  local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local handler = handlers[cmd]
  if handler then
    handler(arg)
  elseif cmd == "" then
    TB.Panel.SetShown(not TB.db.shown)
  else
    TB.Say("/trailblazer [history|milestones|stats|options|show|hide|lock|unlock|units metric|imperial|calibrate|reset [all]]")
    print("    Diagnostics: debug, strides, perf, whoami")
  end
end

-- Blizzard's addon compartment (the addons button on the minimap), wired up in the TOC.
function Trailblazer_OnCompartmentClick(_, mouseButton)
  if mouseButton == "RightButton" then TB.MilestonesPage.Toggle() else TB.HistoryPage.Toggle() end
end

function Trailblazer_OnCompartmentEnter(_, button)
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:AddLine("Trailblazer")
  GameTooltip:AddDoubleLine("Distance today", TB.Distance(TB.History.DistanceToday()), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Steps today", TB.Grouped(TB.History.StepsToday()), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddLine("Left-click for history, right-click for milestones", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

function Trailblazer_OnCompartmentLeave()
  GameTooltip:Hide()
end
