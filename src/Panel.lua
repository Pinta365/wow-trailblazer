local _, TB = ...

-- The small movable panel: steps today, the session so far and what the character is
-- doing. Its tooltip breaks the session and all-time totals down by mode and gait.
local Panel = {}
TB.Panel = Panel

local panel

local function ledgerLines(tip, title, ledger)
  tip:AddLine(title, 1, 0.82, 0)
  tip:AddDoubleLine("Steps", TB.Grouped(ledger.steps), 1, 1, 1, 1, 1, 1)
  tip:AddDoubleLine("Jumps", TB.Grouped(ledger.jumps), 1, 1, 1, 1, 1, 1)
  if ledger.mountJumps > 0 then
    tip:AddDoubleLine("Mount jumps", TB.Grouped(ledger.mountJumps), 1, 1, 1, 1, 1, 1)
  end
  for _, mode in ipairs(TB.MODES) do
    local yards = ledger.yards[mode]
    if yards >= TB.MIN_SHOWN_YARDS then
      tip:AddDoubleLine(TB.MODE_LABEL[mode], TB.Distance(yards), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    for _, gait in ipairs(TB.STYLES_OF[mode] or {}) do
      local yards = ledger.gaitYards[gait]
      if yards >= TB.MIN_SHOWN_YARDS then
        local amount = mode == "foot"
          and ("%s steps  ·  %s"):format(TB.Grouped(ledger.gaitSteps[gait]), TB.Distance(yards))
          or TB.Distance(yards)
        tip:AddDoubleLine("   " .. TB.GAIT_LABEL[gait], amount, 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
      end
    end
    if mode == "taxi" and ledger.flights > 0 then
      tip:AddDoubleLine("   Fares", TB.FlightsText(ledger.flights, ledger.spent), 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
    end
  end
  if ledger.guessed > 0 then
    -- Part of the totals above, not its own mode: distance assumed at run speed when
    -- neither position nor speed could be read (combat inside dungeons).
    tip:AddDoubleLine("Estimated, in dungeon combat", TB.Distance(ledger.guessed), 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
  end
end

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Trailblazer")
  ledgerLines(GameTooltip, "This session", TB.session)
  GameTooltip:AddLine(" ")
  ledgerLines(GameTooltip, "All time", TB.char.lifetime)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Right-click for history  ·  /trailblazer for commands", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

-- What the character is doing right now, in words.
local function activity()
  local p = TB.Motion.probe
  if p.mode == "foot" or p.mode == "swim" then
    return TB.GAIT_LABEL[p.gait] or TB.MODE_LABEL[p.mode]
  end
  if p.mode == "idle" then return "Standing still" end
  return TB.MODE_LABEL[p.mode] or p.mode
end

local function sessionDistance()
  local sum = 0
  for _, yards in pairs(TB.session.yards) do sum = sum + yards end
  return sum
end

-- What the panel last showed; text is only rebuilt when something visible changes.
local shown = {}

-- Records `values` as shown and reports whether any differ from last time.
local function changed(...)
  local differs = false
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if shown[i] ~= v then shown[i], differs = v, true end
  end
  return differs
end

function Panel.Refresh()
  if not panel or not panel:IsShown() then return end
  local byDistance = TB.db.headline == "distance"
  local todaySteps, sessionSteps = TB.History.StepsToday(), TB.session.steps
  local todayYards = byDistance and TB.History.DistanceToday() or 0
  local sessionYards = byDistance and sessionDistance() or TB.session.yards.foot
  local doing = activity()
  -- Compared at the precision shown: whole steps, and 10 yd for distances.
  local floor = math.floor
  if not changed(floor(todaySteps + 0.5), floor(sessionSteps + 0.5), floor(todayYards / 10),
      floor(sessionYards / 10), doing, TB.db.units, TB.db.headline, TB.db.debug)
    and not TB.db.debug then
    return
  end

  if byDistance then
    panel.big:SetText(TB.Distance(todayYards) .. " today")
    panel.small:SetText(("Session %s  ·  %s steps"):format(TB.Distance(sessionYards), TB.Grouped(sessionSteps)))
  else
    panel.big:SetText(TB.Grouped(todaySteps) .. " steps today")
    panel.small:SetText(("Session %s  ·  %s"):format(TB.Grouped(sessionSteps), TB.Distance(sessionYards)))
  end
  panel.now:SetText(doing)

  if TB.db.debug then
    local p = TB.Motion.probe
    panel.probe:SetText(("%s | %s | %s | %.1f yd/s (moved %.1f) | stride %.2f | %s"):format(
      p.source, p.mode, p.gait, p.speed, p.moved, p.stride, TB.Strides.BodyKey()))
    panel.probe:Show()
  else
    panel.probe:Hide()
  end
  panel:SetWidth(math.max(panel.big:GetStringWidth(), panel.small:GetStringWidth(),
    panel.now:GetStringWidth(), TB.db.debug and panel.probe:GetStringWidth() or 0) + 24)
  panel:SetHeight(TB.db.debug and 76 or 60)
end

function Panel.Place()
  local a = TB.db.anchor
  panel:ClearAllPoints()
  panel:SetPoint(a.point, UIParent, a.point, a.x, a.y)
end

function Panel.SetShown(shown)
  TB.db.shown = shown
  if panel then
    panel:SetShown(shown)
    Panel.Refresh()
  end
end

function Panel.Build()
  panel = CreateFrame("Frame", "TrailblazerPanel", UIParent, "BackdropTemplate")
  panel:SetSize(180, 46)
  panel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  panel:SetBackdropColor(0, 0, 0, 0.55)
  panel:SetBackdropBorderColor(0.5, 0.82, 0.73, 0.6)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")

  panel.big = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.big:SetPoint("TOPLEFT", 12, -8)
  panel.small = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.small:SetPoint("TOPLEFT", panel.big, "BOTTOMLEFT", 0, -4)
  panel.now = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.now:SetPoint("TOPLEFT", panel.small, "BOTTOMLEFT", 0, -4)
  panel.probe = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.probe:SetPoint("TOPLEFT", panel.now, "BOTTOMLEFT", 0, -4)

  panel:SetScript("OnDragStart", function(self)
    if not TB.db.locked then self:StartMoving() end
  end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    TB.db.anchor.point, TB.db.anchor.x, TB.db.anchor.y = point, x, y
  end)
  panel:SetScript("OnMouseUp", function(_, mouseButton)
    if mouseButton == "RightButton" then TB.HistoryPage.Toggle() end
  end)
  panel:SetScript("OnEnter", showTooltip)
  panel:SetScript("OnLeave", GameTooltip_Hide)

  Panel.Place()
  panel:SetShown(TB.db.shown)
  Panel.Refresh()
  -- Movement samples redraw the panel; this slow tick only catches the midnight rollover.
  C_Timer.NewTicker(60, Panel.Refresh)
end
