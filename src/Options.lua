local _, TB = ...

-- Trailblazer's page under Options > AddOns, built on Blizzard's vertical settings list.
-- Proxy settings read and write TB.db directly, so slash commands and this page stay in sync.
local Options = {}
TB.Options = Options

local category

local function proxy(variable, varType, name, default, get, set)
  return Settings.RegisterProxySetting(category, "TRAILBLAZER_" .. variable, varType, name, default, get, set)
end

local function checkbox(variable, name, default, tooltip, get, set)
  local setting = proxy(variable, Settings.VarType.Boolean, name, default,
    function() return get() == true end, set)
  Settings.CreateCheckbox(category, setting, tooltip)
end

-- Blizzard asserts that buttons say whether they appear in the options search.
local function addButton(layout, name, buttonText, onClick, tooltip)
  layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
end

-- Opening one of our windows from the options page: close the page so it isn't on top.
local function fromOptions(open)
  return function()
    HideUIPanel(SettingsPanel)
    open()
  end
end

function Options.Register()
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("Trailblazer")

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Panel"))
  checkbox("SHOWN", "Show panel", true, "The small panel with today's steps or distance and your current activity.",
    function() return TB.db.shown end,
    function(value) TB.Panel.SetShown(value) end)
  local headline = proxy("HEADLINE", Settings.VarType.String, "Panel headline", "steps",
    function() return TB.db.headline end,
    function(value) TB.db.headline = value; TB.Panel.Refresh() end)
  Settings.CreateDropdown(category, headline, function()
    local container = Settings.CreateControlTextContainer()
    container:Add("steps", "Steps today")
    container:Add("distance", "Distance today")
    return container:GetData()
  end, "What the panel shows in large text. Distance counts every way of travelling, mounted and flying included.")
  checkbox("LOCKED", "Lock panel position", false, "Stop the panel from being dragged.",
    function() return TB.db.locked end,
    function(value) TB.db.locked = value end)
  checkbox("DEBUG", "Show debug readout", false,
    "Adds a line to the panel with the position source, mode, gait, speed and stride in use.",
    function() return TB.db.debug end,
    function(value) TB.db.debug = value; TB.Panel.Refresh() end)
  addButton(layout, "Panel position", "Reset",
    function()
      TB.db.anchor.point, TB.db.anchor.x, TB.db.anchor.y = "CENTER", 0, -180
      TB.Panel.Place()
    end, "Move the panel back to its starting spot.")

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Display"))
  local units = proxy("UNITS", Settings.VarType.String, "Units", "km",
    function() return TB.db.units end,
    function(value) TB.db.units = value; TB.Panel.Refresh() end)
  Settings.CreateDropdown(category, units, function()
    local container = Settings.CreateControlTextContainer()
    container:Add("km", "Metric (km, m)")
    container:Add("mi", "Imperial (mi, ft)")
    return container:GetData()
  end, "Units for every distance Trailblazer shows.")

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Calibration and history"))
  checkbox("ONE_FOOT", "Count one foot when calibrating", false,
    "Doubles the footfall count you enter, for characters whose steps are too quick to count.",
    function() return TB.db.countOneFoot end,
    function(value) TB.db.countOneFoot = value end)
  addButton(layout, "Stride calibration", "Open",
    fromOptions(TB.Calib.Open), "Measure your own stride lengths for this race and sex.")
  addButton(layout, "Travel history", "Open",
    fromOptions(TB.HistoryPage.Open), "Charts of steps and distance by day, month and year.")
  addButton(layout, "Milestones", "Open",
    fromOptions(TB.MilestonesPage.Open), "Travel achievements in Bronze, Silver, Gold and Legendary tiers.")

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Totals"))
  addButton(layout, "Session totals", "Reset",
    function()
      TB.session = TB.NewLedger()
      TB.Panel.Refresh()
      TB.Say("Session totals reset.")
    end, "Start this session's counts from zero.")
  addButton(layout, "All totals for this character", "Erase",
    function() StaticPopup_Show("TRAILBLAZER_WIPE") end,
    "Erase this character's lifetime totals and history. Other characters are kept.")

  Settings.RegisterAddOnCategory(category)
end

function Options.Open()
  Settings.OpenToCategory(category:GetID())
end
