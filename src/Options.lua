local _, TB = ...

-- Trailblazer's page under Options > AddOns, built on Blizzard's vertical settings list.
-- Proxy settings read and write TB.db directly, so slash commands and this page stay in sync.
local Options = {}
TB.Options = Options

local category
local settings = {}  -- every registered setting, for "Reset all settings"

local function proxy(variable, varType, name, default, get, set)
  local setting = Settings.RegisterProxySetting(category, "TRAILBLAZER_" .. variable, varType, name, default, get, set)
  table.insert(settings, setting)
  return setting
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

local function resetPanelPosition()
  local a = TB.DEFAULTS.anchor
  TB.db.anchor.point, TB.db.anchor.x, TB.db.anchor.y = a.point, a.x, a.y
  TB.Panel.Place()
end

-- Back to TB.DEFAULTS for every preference, through the settings so the page redraws.
-- Totals, history, milestones and stride calibrations are data and are kept.
local function resetSettings()
  for _, setting in ipairs(settings) do setting:SetValueToDefault() end
  resetPanelPosition()
  TB.db.chart = CopyTable(TB.DEFAULTS.chart)
  TB.HistoryPage.Redraw()
  TB.Say("All settings reset to their defaults.")
end

StaticPopupDialogs.TRAILBLAZER_RESET_SETTINGS = {
  text = "Reset all Trailblazer settings to their defaults? Your totals, history, milestones and stride calibrations are kept.",
  button1 = YES,
  button2 = NO,
  OnAccept = resetSettings,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Opening one of our windows from the options page: close the page so it isn't on top.
local function fromOptions(open)
  return function()
    HideUIPanel(SettingsPanel)
    open()
  end
end

function Options.Register()
  local defaults = TB.DEFAULTS
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("Trailblazer")

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Panel"))
  checkbox("SHOWN", "Show panel", defaults.shown, "The small panel with today's steps or distance and your current activity.",
    function() return TB.db.shown end,
    function(value) TB.Panel.SetShown(value) end)
  checkbox("MINIMAP", "Show minimap button", not defaults.minimap.hide,
    "A button on the minimap's edge: left-click for history, right-click for milestones, middle-click for options. Trailblazer is also in the minimap's addons menu.",
    function() return not TB.db.minimap.hide end,
    function(value) TB.Broker.SetMinimapShown(value) end)
  local headline = proxy("HEADLINE", Settings.VarType.String, "Panel headline", defaults.headline,
    function() return TB.db.headline end,
    function(value) TB.db.headline = value; TB.Panel.Refresh() end)
  Settings.CreateDropdown(category, headline, function()
    local container = Settings.CreateControlTextContainer()
    container:Add("steps", "Steps today")
    container:Add("distance", "Distance today")
    return container:GetData()
  end, "What the panel shows in large text. Distance counts every way of travelling, mounted and flying included.")
  checkbox("LOCKED", "Lock panel position", defaults.locked, "Stop the panel from being dragged.",
    function() return TB.db.locked end,
    function(value) TB.db.locked = value end)
  checkbox("DEBUG", "Show debug readout", defaults.debug,
    "Adds a line to the panel with the position source, mode, gait, speed and stride in use.",
    function() return TB.db.debug end,
    function(value) TB.db.debug = value; TB.Panel.Refresh() end)
  addButton(layout, "Panel position", "Reset", resetPanelPosition,
    "Move the panel back to its starting spot.")

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Display"))
  local units = proxy("UNITS", Settings.VarType.String, "Units", defaults.units,
    function() return TB.db.units end,
    function(value) TB.db.units = value; TB.Panel.Refresh() end)
  Settings.CreateDropdown(category, units, function()
    local container = Settings.CreateControlTextContainer()
    container:Add("km", "Metric (km, m)")
    container:Add("mi", "Imperial (mi, ft)")
    return container:GetData()
  end, "Units for every distance Trailblazer shows.")

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Calibration and history"))
  checkbox("ONE_FOOT", "Count one foot when calibrating", defaults.countOneFoot,
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

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Settings"))
  addButton(layout, "All settings", "Reset",
    function() StaticPopup_Show("TRAILBLAZER_RESET_SETTINGS") end,
    "Put every setting on this page, the panel position and the history chart's choices back to their defaults. Totals, history, milestones and stride calibrations are kept.")

  Settings.RegisterAddOnCategory(category)
end

-- The Trailblazer window is closed first; it would sit on top of the options page.
function Options.Open()
  TB.Window.Close()
  Settings.OpenToCategory(category:GetID())
end
