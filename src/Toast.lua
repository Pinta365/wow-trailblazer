local _, TB = ...

-- The banner that slides in when a milestone tier is reached; clicking it opens the
-- Milestones tab on that milestone's category. Several at once queue up.
local Toast = {}
TB.Toast = Toast

local Milestones = TB.Milestones
local TIERS = Milestones.TIERS

local FADE_IN, HOLD, FADE_OUT = 0.25, 4, 0.8
local toast
local queue = {}

local function buildToast()
  toast = CreateFrame("Button", nil, UIParent)
  toast:SetSize(340, 72)
  toast:SetPoint("TOP", 0, -140)
  toast:SetFrameStrata("HIGH")
  local bg = toast:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)
  toast.edges = {}
  for i, point in ipairs({ "TOP", "BOTTOM" }) do
    local edge = toast:CreateTexture(nil, "ARTWORK")
    edge:SetHeight(2)
    edge:SetPoint(point .. "LEFT")
    edge:SetPoint(point .. "RIGHT")
    toast.edges[i] = edge
  end
  toast.icon = toast:CreateTexture(nil, "ARTWORK")
  toast.icon:SetSize(48, 48)
  toast.icon:SetPoint("LEFT", 12, 0)
  toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 12, 0)
  toast.title:SetText("Milestone reached")
  toast.name = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  toast.name:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -3)
  toast.tier = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  toast.tier:SetPoint("TOPLEFT", toast.name, "BOTTOMLEFT", 0, -3)
  toast:SetScript("OnClick", function(self) TB.MilestonesPage.Open(self.milestone) end)
  toast:Hide()
end

local function nextToast()
  local item = table.remove(queue, 1)
  if not item then
    toast:Hide()
    return
  end
  local m, tier = item[1], item[2]
  toast.milestone = m
  local info = TIERS[tier]
  local c = info.color
  toast.icon:SetTexture(Milestones.Icon(m))
  toast.name:SetText(m.name)
  toast.tier:SetText(("%s  ·  +%d points"):format(info.name, info.points))
  toast.tier:SetTextColor(c[1], c[2], c[3])
  for _, edge in ipairs(toast.edges) do edge:SetColorTexture(c[1], c[2], c[3], 1) end
  local sound = tier == 4 and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.UI_DIG_SITE_COMPLETION_TOAST
  if sound then PlaySound(sound) end
  toast.started = GetTime()
  toast:SetAlpha(0)
  toast:Show()
end

local function animate(self)
  local t = GetTime() - self.started
  if t < FADE_IN then
    self:SetAlpha(t / FADE_IN)
  elseif t < FADE_IN + HOLD or self:IsMouseOver() then
    self:SetAlpha(1)
    if t >= FADE_IN + HOLD then self.started = GetTime() - FADE_IN - HOLD end
  elseif t < FADE_IN + HOLD + FADE_OUT then
    self:SetAlpha(1 - (t - FADE_IN - HOLD) / FADE_OUT)
  else
    nextToast()
  end
end

function Toast.Show(m, tier)
  if not toast then
    buildToast()
    toast:SetScript("OnUpdate", animate)
  end
  TB.Say("Milestone reached: %s (%s)", m.name, TIERS[tier].name)
  queue[#queue + 1] = { m, tier }
  if not toast:IsShown() then nextToast() end
  TB.MilestonesPage.Refresh()
end
