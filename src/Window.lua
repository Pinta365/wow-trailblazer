local _, TB = ...

-- The Trailblazer window: one frame with a tab per page (History, Milestones). Each page
-- registers a builder and draws into its own pane, which fills the window.
local Window = {}
TB.Window = Window

Window.WIDTH, Window.HEIGHT = 744, 418

local frame
local pages = {}      -- in tab order: { id, label, build, pane }
local current

local function page(id)
  for i, p in ipairs(pages) do
    if p.id == id then return p, i end
  end
end

-- Registered at file load; the pane is built the first time its tab is shown.
function Window.Register(id, label, build)
  pages[#pages + 1] = { id = id, label = label, build = build }
end

local function showPage(id)
  local p, index = page(id)
  if not p.pane then
    p.pane = CreateFrame("Frame", nil, frame)
    p.pane:SetAllPoints()
    p.pane:Hide()
    p.build(p.pane)
  end
  for _, other in ipairs(pages) do
    if other.pane and other ~= p then other.pane:Hide() end
  end
  current = id
  PanelTemplates_SetTab(frame, index)
  p.pane:Show()
end

local function build()
  frame = CreateFrame("Frame", "TrailblazerWindow", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(Window.WIDTH, Window.HEIGHT)
  frame:SetPoint("CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame.TitleText:SetText("Trailblazer")
  tinsert(UISpecialFrames, frame:GetName())

  local gear = CreateFrame("Button", nil, frame)
  gear:SetSize(18, 18)
  gear:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
  gear:SetNormalAtlas("questlog-icon-setting")
  gear:SetHighlightAtlas("questlog-icon-setting", "ADD")
  gear:SetScript("OnClick", function() TB.Options.Open() end)
  gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Options")
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", GameTooltip_Hide)

  for i, p in ipairs(pages) do
    local tab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(p.label)
    PanelTemplates_TabResize(tab, 0)
    if i == 1 then
      tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    else
      tab:SetPoint("LEFT", frame.Tabs[i - 1], "RIGHT", 3, 0)
    end
    tab:SetScript("OnClick", function() showPage(p.id) end)
  end
  PanelTemplates_SetNumTabs(frame, #pages)
  frame:Hide()
end

-- Opens the window on a page, or closes it when that page is already showing.
function Window.Toggle(id)
  if not frame then build() end
  if frame:IsShown() and current == id then
    frame:Hide()
  else
    showPage(id)
    frame:Show()
  end
end

function Window.Close()
  if frame then frame:Hide() end
end

function Window.Open(id)
  if not frame then build() end
  showPage(id)
  frame:Show()
end
