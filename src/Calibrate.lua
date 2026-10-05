local _, TB = ...

-- Stride calibration: record on-foot yards while the player counts footfalls, then
-- divide. Shared by the calibration window and the /trailblazer calibrate subcommands.
local Calib = {}
TB.Calib = Calib

local MIN_YARDS = 5
local SINGLE_GAIT_SHARE = 0.85

function Calib.Active()
  return TB.Motion.trial ~= nil
end

function Calib.Start()
  TB.Motion.trial = {}
end

function Calib.Cancel()
  TB.Motion.trial = nil
end

-- The gait holding the most recorded yards, its yards, and the total recorded.
function Calib.Lead()
  local trial = TB.Motion.trial
  if not trial then return nil, 0, 0 end
  local lead, total = nil, 0
  for gait, yards in pairs(trial) do
    total = total + yards
    if not lead or yards > trial[lead] then lead = gait end
  end
  return lead, lead and trial[lead] or 0, total
end

-- Returns true and a summary on success, or false and the reason. A missing count or
-- too little movement keeps the recording going; mixed gaits end it.
function Calib.Finish(footfalls)
  if not Calib.Active() then return false, "No calibration is running." end
  if not footfalls or footfalls < 1 then return false, "Enter how many footfalls you counted." end
  local gait, yards, total = Calib.Lead()
  if not gait or total < MIN_YARDS then
    return false, "Too little movement recorded yet; keep going."
  end
  if yards < total * SINGLE_GAIT_SHARE then
    Calib.Cancel()
    return false, ("Mixed gaits (%d%% %s); start again holding one gait."):format(
      yards / total * 100, TB.GAIT_LABEL[gait]:lower())
  end
  Calib.Cancel()
  local stride = yards / footfalls
  local average, runs = TB.Strides.Save(gait, stride)
  return true, ("This run: %.2f yd per footfall. %s %s stride is now %.2f (average of %d run%s)."):format(
    stride, TB.Strides.BodyKey(), gait, average, runs, runs == 1 and "" or "s")
end

-- Window ---------------------------------------------------------------------------

local win

local function strideSource(gait)
  local _, runs = TB.Strides.Calibration(gait)
  if runs then return ("yours, %d run%s"):format(runs, runs == 1 and "" or "s") end
  local _, builtIn = TB.Strides.Estimate(gait)
  if gait == "walkBack" and not builtIn and TB.Strides.Calibration("walk") then
    return "yours, from walking"
  end
  return builtIn and "built-in" or "default"
end

local function refreshStrides()
  win.body:SetText("Character: " .. TB.Strides.BodyKey())
  for _, gait in ipairs(TB.Strides.PACES) do
    local row = win.rows[gait]
    row.value:SetText(("%.2f yd"):format(TB.Strides.Length(gait)))
    row.source:SetText(strideSource(gait))
  end
end

local function refreshState()
  local recording = Calib.Active()
  win.toggle:SetText(recording and "Cancel" or "Start")
  win.save:SetEnabled(recording)
  if recording then
    local gait, yards = Calib.Lead()
    win.status:SetText(gait
      and ("Recording: %s, %.1f yd"):format(TB.GAIT_LABEL[gait], yards)
      or "Recording: start moving in one gait and count footfalls.")
  else
    win.status:SetText("Press Start, then move in one gait while counting footfalls.")
  end
end

local function showResult(ok, msg)
  win.result:SetText(msg)
  win.result:SetTextColor(ok and 0.5 or 1, ok and 1 or 0.4, ok and 0.5 or 0.4)
  if ok then TB.Say(msg) end
end

local function save()
  local count = tonumber(win.count:GetText())
  if count and win.oneFoot:GetChecked() then count = count * 2 end
  local ok, msg = Calib.Finish(count)
  showResult(ok, msg)
  if ok then win.count:SetText("") end
  win.count:ClearFocus()
  refreshStrides()
  refreshState()
end

StaticPopupDialogs.TRAILBLAZER_FORGET_STRIDES = {
  text = "Remove your own stride calibrations for %s?",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    TB.Strides.Forget()
    if win then refreshStrides() end
    TB.Say("Calibration cleared for %s.", TB.Strides.BodyKey())
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local function button(text, width)
  local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  return b
end

local function build()
  win = CreateFrame("Frame", "TrailblazerCalibration", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(320, 340)
  win:SetPoint("CENTER", 0, 120)
  win:SetFrameStrata("DIALOG")
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win.TitleText:SetText("Trailblazer calibration")
  tinsert(UISpecialFrames, win:GetName())

  win.body = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  win.body:SetPoint("TOPLEFT", 16, -34)

  -- Current strides for this body.
  win.rows = {}
  local anchor = win.body
  for _, gait in ipairs(TB.Strides.PACES) do
    local row = {}
    row.label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    row.label:SetText(TB.GAIT_LABEL[gait])
    row.value = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("LEFT", row.label, "LEFT", 130, 0)
    row.source = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.source:SetPoint("LEFT", row.label, "LEFT", 190, 0)
    win.rows[gait] = row
    anchor = row.label
  end

  win.status = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  win.status:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
  win.status:SetWidth(288)
  win.status:SetJustifyH("LEFT")

  win.toggle = button("Start", 90)
  win.toggle:SetPoint("TOPLEFT", win.status, "BOTTOMLEFT", 0, -10)
  win.toggle:SetScript("OnClick", function()
    if Calib.Active() then Calib.Cancel() else Calib.Start() end
    win.count:ClearFocus()  -- keep movement keys out of the input box
    win.result:SetText("")
    refreshState()
  end)

  local countLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  countLabel:SetPoint("TOPLEFT", win.toggle, "BOTTOMLEFT", 0, -14)
  countLabel:SetText("Footfalls counted:")

  win.count = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
  win.count:SetSize(60, 20)
  win.count:SetPoint("LEFT", countLabel, "RIGHT", 12, 0)
  win.count:SetAutoFocus(false)
  win.count:SetNumeric(true)
  win.count:SetMaxLetters(4)
  win.count:SetScript("OnEnterPressed", save)
  win.count:SetScript("OnEscapePressed", win.count.ClearFocus)

  win.save = button("Save", 70)
  win.save:SetPoint("LEFT", win.count, "RIGHT", 10, 0)
  win.save:SetScript("OnClick", save)

  win.oneFoot = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
  win.oneFoot:SetSize(24, 24)
  win.oneFoot:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", -4, -6)
  win.oneFoot.Text:SetText("I counted one foot only (doubles the count)")
  win.oneFoot:SetChecked(TB.db.countOneFoot)
  win.oneFoot:SetScript("OnClick", function(self) TB.db.countOneFoot = self:GetChecked() end)

  win.result = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.result:SetPoint("TOPLEFT", win.oneFoot, "BOTTOMLEFT", 4, -8)
  win.result:SetWidth(288)
  win.result:SetJustifyH("LEFT")

  local clear = button("Clear mine", 90)
  clear:SetPoint("BOTTOMRIGHT", -12, 12)
  clear:SetScript("OnClick", function()
    StaticPopup_Show("TRAILBLAZER_FORGET_STRIDES", TB.Strides.BodyKey())
  end)

  -- Live yard count while recording; the window costs nothing when closed.
  local since = 0
  win:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.25 then return end
    since = 0
    if Calib.Active() then refreshState() end
  end)
  win:SetScript("OnShow", function()
    win.oneFoot:SetChecked(TB.db.countOneFoot)
    refreshStrides()
    refreshState()
  end)
  win:Hide()
end

function Calib.Toggle()
  if not win then build() end
  win:SetShown(not win:IsShown())
end

function Calib.Open()
  if not win then build() end
  win:Show()
end
