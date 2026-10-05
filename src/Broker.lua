local _, TB = ...

-- A LibDataBroker data source showing the panel's headline, for broker displays (Titan
-- Panel, ChocolateBar...), and a minimap button LibDBIcon builds from it. Both come from
-- the embedded libraries; without them this module does nothing.
local Broker = {}
TB.Broker = Broker

local NAME = "Trailblazer"
local object

local function library(name)
  return LibStub and LibStub(name, true)
end

-- Runs before the panel is built, so the panel's first refresh fills in the text.
function Broker.Start()
  local ldb = library("LibDataBroker-1.1")
  if not ldb then return end
  object = ldb:NewDataObject(NAME, {
    type = "data source",
    label = NAME,
    text = "",
    icon = "Interface\\AddOns\\Trailblazer\\media\\minimap",
    OnClick = function(_, mouseButton)
      if mouseButton == "RightButton" then TB.MilestonesPage.Toggle() else TB.HistoryPage.Toggle() end
    end,
    OnTooltipShow = function(tip)
      TB.Panel.FillTooltip(tip, "Left-click for history, right-click for milestones")
    end,
  })
  local icon = library("LibDBIcon-1.0")
  if icon then icon:Register(NAME, object, TB.db.minimap) end
end

function Broker.Active()
  return object ~= nil
end

function Broker.SetText(text)
  if object then object.text = text end
end

function Broker.SetMinimapShown(shown)
  TB.db.minimap.hide = not shown
  local icon = library("LibDBIcon-1.0")
  if not icon then return end
  if shown then icon:Show(NAME) else icon:Hide(NAME) end
end
