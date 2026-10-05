local _, TB = ...

-- The Milestones tab of the Trailblazer window: one category at a time, as cards in a
-- 2 x 3 grid.
local Page = {}
TB.MilestonesPage = Page

local Milestones = TB.Milestones
local TIERS = Milestones.TIERS
local CARD_H, CARD_GAP, COLUMNS, ROWS = 96, 10, 2, 3
local CARD_W = (TB.Window.WIDTH - 32 - (COLUMNS - 1) * CARD_GAP) / COLUMNS
local PIP, PIP_GAP = 10, 3

-- "2026-10-05" -> "05 Oct 2026" ("05 Oct" when `short` and it is this year); the
-- before-tracking marker reads as such.
local function niceDate(stamp, short)
  if Milestones.WasBeforeTracking(stamp) then return "before tracking" end
  local y, m, d = stamp:match("^(%d+)-(%d+)-(%d+)$")
  if not y then return stamp end
  local format = short and y == date("%Y") and "%d %b" or "%d %b %Y"
  return date(format, time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
end

local win
local category = Milestones.CATEGORIES[1].id

local function showCardTooltip(card)
  local m = card.milestone
  if not m then return end
  local got = Milestones.Reached(m)
  local value = Milestones.Value(m)
  GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
  GameTooltip:AddLine(m.name)
  GameTooltip:AddLine(m.text, 1, 1, 1, true)
  GameTooltip:AddLine(" ")
  for tier, info in ipairs(TIERS) do
    local goal = m.goals[tier]
    if goal then
      local c = info.color
      local status
      if got[tier] then
        status = "Reached " .. niceDate(got[tier])
      else
        status = Milestones.Format(m, goal - value) .. " to go"
      end
      GameTooltip:AddDoubleLine(("%s  %s  (%d pts)"):format(info.name, Milestones.Format(m, goal), info.points),
        status, c[1], c[2], c[3], 0.8, 0.8, 0.8)
    end
  end
  GameTooltip:Show()
end

local function renderCard(card, m)
  card.milestone = m
  if not m then
    card:Hide()
    return
  end
  local got = Milestones.Reached(m)
  local value = Milestones.Value(m)
  local best = 0
  for tier = 1, 4 do
    if got[tier] then best = tier end
  end

  card.icon:SetTexture(Milestones.Icon(m))
  card.icon:SetDesaturated(best == 0)
  card.name:SetText(m.name)
  card.text:SetText(m.text)
  -- Earned tiers show in the highest tier's colour: the left strip, a border around the
  -- icon, a faint wash over the card and the status line.
  local tier, goal = Milestones.NextTier(m)
  local earned = best > 0
  local scopeTag = m.scope == "account" and "|cff9a9a9aAccount|r  ·  " or ""
  if earned then
    local c = TIERS[best].color
    card.accent:SetColorTexture(c[1], c[2], c[3], 1)
    card.iconBorder:SetColorTexture(c[1], c[2], c[3], 1)
    card.tint:SetColorTexture(c[1], c[2], c[3], 0.08)
    -- The bar shows the next tier in its colour, so the status line doesn't name it.
    local status = ("%s reached %s"):format(TIERS[best].name, niceDate(got[best], true))
    card.status:SetText(scopeTag .. status)
    card.status:SetTextColor(c[1], c[2], c[3])
  else
    card.status:SetText(scopeTag .. "Next: " .. TIERS[tier].name)
    card.status:SetTextColor(0.5, 0.5, 0.5)
  end
  card.accent:SetShown(earned)
  card.iconBorder:SetShown(earned)
  card.tint:SetShown(earned)

  if tier then
    local c = TIERS[tier].color
    card.bar:SetStatusBarColor(c[1], c[2], c[3])
    card.bar:SetMinMaxValues(0, goal)
    card.bar:SetValue(math.min(value, goal))
    card.barText:SetText(("%s / %s"):format(Milestones.Format(m, math.min(value, goal)), Milestones.Format(m, goal)))
  else
    local c = TIERS[best].color
    card.bar:SetStatusBarColor(c[1], c[2], c[3])
    card.bar:SetMinMaxValues(0, 1)
    card.bar:SetValue(1)
    card.barText:SetText("Complete")
  end

  -- One pip per tier the milestone has, lit in its colour once reached.
  local x = 0
  for t = 4, 1, -1 do
    local pip = card.pips[t]
    if m.goals[t] then
      local c = TIERS[t].color
      if got[t] then pip:SetColorTexture(c[1], c[2], c[3], 1) else pip:SetColorTexture(0.25, 0.25, 0.25, 1) end
      pip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10 - x, -12)
      x = x + PIP + PIP_GAP
      pip:Show()
    else
      pip:Hide()
    end
  end
  card:Show()
end

local function render()
  local charPoints, charTiers, charTotal = Milestones.Score("char")
  local accPoints, accTiers, accTotal = Milestones.Score("account")
  win.score:SetText(("This character: |cffffffff%d pts|r (%d / %d tiers)     Account: |cffffffff%d pts|r (%d / %d tiers)")
    :format(charPoints, charTiers, charTotal, accPoints, accTiers, accTotal))

  for id, b in pairs(win.catButtons) do
    if id == category then b:LockHighlight() else b:UnlockHighlight() end
  end

  local slot = 0
  for _, m in ipairs(Milestones.LIST) do
    if m.cat == category then
      slot = slot + 1
      if win.cards[slot] then renderCard(win.cards[slot], m) end
    end
  end
  for i = slot + 1, #win.cards do renderCard(win.cards[i], nil) end

  for _, card in ipairs(win.cards) do
    if GameTooltip:IsOwned(card) then showCardTooltip(card) end
  end
end

local function buildCard(i)
  local card = CreateFrame("Frame", nil, win)
  card:SetSize(CARD_W, CARD_H)
  local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
  card:SetPoint("TOPLEFT", 16 + col * (CARD_W + CARD_GAP), -92 - row * (CARD_H + CARD_GAP))
  card:EnableMouse(true)
  card:SetScript("OnEnter", showCardTooltip)
  card:SetScript("OnLeave", GameTooltip_Hide)

  local bg = card:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  -- A strip down the left edge in the colour of the highest tier reached.
  card.accent = card:CreateTexture(nil, "ARTWORK")
  card.accent:SetPoint("TOPLEFT")
  card.accent:SetPoint("BOTTOMLEFT")
  card.accent:SetWidth(3)

  card.tint = card:CreateTexture(nil, "BACKGROUND", nil, 1)
  card.tint:SetAllPoints()

  card.icon = card:CreateTexture(nil, "ARTWORK")
  card.icon:SetSize(44, 44)
  card.icon:SetPoint("TOPLEFT", 12, -10)
  card.iconBorder = card:CreateTexture(nil, "BORDER")
  card.iconBorder:SetPoint("TOPLEFT", card.icon, -2, 2)
  card.iconBorder:SetPoint("BOTTOMRIGHT", card.icon, 2, -2)

  card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
  card.name:SetPoint("RIGHT", -64, 0)
  card.name:SetJustifyH("LEFT")
  card.name:SetWordWrap(false)
  card.text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  card.text:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
  card.text:SetPoint("RIGHT", -10, 0)
  card.text:SetJustifyH("LEFT")
  card.text:SetTextColor(0.7, 0.7, 0.7)
  card.status = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  card.status:SetPoint("TOPLEFT", card.text, "BOTTOMLEFT", 0, -3)
  card.status:SetPoint("RIGHT", -10, 0)
  card.status:SetJustifyH("LEFT")
  card.status:SetWordWrap(false)

  card.bar = CreateFrame("StatusBar", nil, card)
  card.bar:SetSize(130, 10)
  card.bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 66, 12)
  card.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  local barBg = card.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(1, 1, 1, 0.08)
  card.barText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  card.barText:SetPoint("LEFT", card.bar, "RIGHT", 6, 0)

  card.pips = {}
  for t = 1, 4 do
    local pip = card:CreateTexture(nil, "ARTWORK")
    pip:SetSize(PIP, PIP)
    card.pips[t] = pip
  end
  return card
end

-- Draws the Milestones page into its pane of the Trailblazer window.
local function build(pane)
  win = CreateFrame("Frame", nil, pane)
  win:SetAllPoints()

  win.score = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  win.score:SetPoint("TOPLEFT", 18, -32)

  -- One button per category, spread across the width.
  win.catButtons = {}
  local count = #Milestones.CATEGORIES
  local width = (TB.Window.WIDTH - 32 - (count - 1) * 4) / count
  for i, cat in ipairs(Milestones.CATEGORIES) do
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * (width + 4), -56)
    b:SetText(cat.name)
    b:SetScript("OnClick", function()
      category = cat.id
      render()
    end)
    win.catButtons[cat.id] = b
  end

  win.cards = {}
  for i = 1, COLUMNS * ROWS do win.cards[i] = buildCard(i) end

  win:SetScript("OnShow", render)
end

TB.Window.Register("milestones", "Milestones", build)

function Page.Toggle()
  TB.Window.Toggle("milestones")
end

-- Opens the Milestones tab, on the category of milestone `m` when given.
function Page.Open(m)
  if m then category = m.cat end
  TB.Window.Open("milestones")
  Page.Refresh()
end

function Page.Refresh()
  if win and win:IsVisible() then render() end
end
