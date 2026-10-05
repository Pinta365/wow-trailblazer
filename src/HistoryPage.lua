local _, TB = ...

-- The History tab of the Trailblazer window: bar charts of steps or distance per day (week
-- and month views) or per month (year view), for one character or all of them, with a
-- ranking of characters beside the chart.
local HistoryPage = {}
TB.HistoryPage = HistoryPage

local CHART_W = 440
local CHART_H = TB.Window.HEIGHT - 186
local MAX_BARS = 31
local LIST_W, ROW_H, MAX_ROWS = 200, 18, 9
local TOP_CONTRIBUTORS = 5
local GROW_TIME, GROW_STAGGER = 0.4, 0.012
local DIMMED = 0.2

local MODE_COLOR = {
  foot    = { 0.50, 0.82, 0.73 },
  mount   = { 0.93, 0.62, 0.30 },
  shapeshift = { 0.45, 0.72, 0.30 },
  swim    = { 0.36, 0.60, 0.95 },
  air     = { 0.72, 0.58, 0.90 },
  vehicle = { 0.60, 0.60, 0.60 },
  taxi    = { 0.95, 0.85, 0.35 },
  transport = { 0.92, 0.42, 0.42 },
  ghost   = { 0.62, 0.90, 0.95 },
}
local LEGEND_GAP, LEGEND_ROW = 14, 16

local WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local win
local offset = 0  -- 0 = current period, -1 = the one before, ...

-- Date helpers. Noon avoids daylight-saving edges when stepping by whole days.
local function noon(y, m, d) return time({ year = y, month = m, day = d, hour = 12 }) end
local function dayKeyOf(t) return date("%Y-%m-%d", t) end

-- The bars for the current view: list of { key, label, record, title, short, future,
-- today }. Everything but the records only changes with the view, the period shown or
-- the date, so it is built once and kept; records are looked up on every redraw.
local layout = { bars = {}, title = "" }

local function buildLayout(view)
  local now = date("*t")
  local todayKey = date("%Y-%m-%d")
  local bars, title = {}, ""

  if view == "week" then
    local monday = now.day - (now.wday + 5) % 7 + 7 * offset
    for i = 0, 6 do
      local t = noon(now.year, now.month, monday + i)  -- time() normalises day overflow
      local key = dayKeyOf(t)
      bars[#bars + 1] = { key = key, label = WEEKDAYS[i + 1],
        title = date("%a %d %b %Y", t), short = date("%a %d %b", t),
        future = key > todayKey, today = key == todayKey }
    end
    title = ("%s - %s"):format(date("%d %b", noon(now.year, now.month, monday)),
      date("%d %b %Y", noon(now.year, now.month, monday + 6)))
  elseif view == "month" then
    local index = now.year * 12 + (now.month - 1) + offset
    local y, m = math.floor(index / 12), index % 12 + 1
    local length = date("*t", noon(y, m + 1, 0)).day
    for d = 1, length do
      local key = ("%04d-%02d-%02d"):format(y, m, d)
      bars[#bars + 1] = { key = key, label = (d == 1 or d % 5 == 0) and tostring(d) or "",
        title = date("%a %d %b %Y", noon(y, m, d)),
        short = date("%a %d %b", noon(y, m, d)), future = key > todayKey, today = key == todayKey }
    end
    title = ("%s %d"):format(MONTHS[m], y)
  else
    local y = now.year + offset
    local thisMonth = todayKey:sub(1, 7)
    for m = 1, 12 do
      local key = ("%04d-%02d"):format(y, m)
      bars[#bars + 1] = { key = key, label = MONTHS[m]:sub(1, 1),
        title = ("%s %d"):format(MONTHS[m], y), short = MONTHS[m], future = key > thisMonth, today = key == thisMonth }
    end
    title = tostring(y)
  end
  for _, b in ipairs(bars) do b.sum = { yards = {} } end
  layout.bars, layout.title = bars, title
end

local function periodBars(view, scope)
  local layoutKey = ("%s%d%s"):format(view, offset, (TB.History.Today()))
  if layout.key ~= layoutKey then
    layout.key = layoutKey
    buildLayout(view)
  end
  local kind = view == "year" and "months" or "days"
  for _, b in ipairs(layout.bars) do
    b.record = TB.History.Lookup(scope, kind, b.key, b.sum)
  end
  return layout.bars, layout.title
end

-- Distance counts only the travel modes switched on in the legend.
local function totalYards(record)
  local hidden, sum = TB.db.chart.hidden, 0
  for mode, yards in pairs(record.yards) do
    if not hidden[mode] then sum = sum + yards end
  end
  return sum
end

-- The plotted number for a record in the current metric (yards for distance).
local function valueOf(record)
  if not record then return 0 end
  if TB.db.chart.metric == "distance" then return totalYards(record) end
  return record.steps
end

local function formatValue(v)
  if TB.db.chart.metric == "distance" then return TB.Distance(v) end
  return TB.Grouped(v)
end

-- Axis labels without trailing zeros: "2 km", "500", "1.5 mi".
local function axisLabel(v)
  if TB.db.chart.metric ~= "distance" then return TB.Grouped(v) end
  local units = v / TB.YardsPerUnit()
  return ("%s %s"):format(tostring(math.floor(units * 100 + 0.5) / 100), TB.db.units)
end

-- Round the axis up to 1, 2 or 5 times a power of ten.
local function niceCeiling(v)
  if v <= 0 then return 1 end
  local p = 10 ^ math.floor(math.log10(v))
  for _, f in ipairs({ 1, 2, 5, 10 }) do
    if v <= f * p then return f * p end
  end
end

local function classColor(class)
  local c = class and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 0.8, 0.8, 0.8
end

-- Full name: main name plus surname, which together are unique across the region.
local function shortName(char)
  if char.surname then return char.name .. " " .. char.surname end
  return char.name or "?"
end

local function barKind()
  return TB.db.chart.view == "year" and "months" or "days"
end

-- Characters with travel in the given keys, largest first: { guid, char, total }.
local function rankCharacters(keys)
  local kind, rows = barKind(), {}
  for guid, char in pairs(TB.db.chars) do
    local total = 0
    for _, key in ipairs(keys) do total = total + valueOf(char[kind][key]) end
    if total > 0 then rows[#rows + 1] = { guid = guid, char = char, total = total } end
  end
  table.sort(rows, function(a, b) return a.total > b.total end)
  return rows
end


-- The character a single-character scope shows.
local function scopeChar(scope)
  if scope == "char" then return TB.char end
  return TB.db.chars[scope]
end

-- Distance can stack by travel mode: always for one character, and for all characters
-- when chosen with the "By travel" toggle. Steps have no per-mode split.
local function stackByMode(cfg)
  return cfg.metric == "distance" and (cfg.scope ~= "account" or cfg.stack == "mode")
end

-- What each bar is stacked from: characters in class colours (largest at the bottom, in
-- the order of the list beside the chart), or travel modes.
local function chartLayers(cfg, rows, layers)
  wipe(layers)
  if cfg.scope == "account" and not stackByMode(cfg) then
    for i, row in ipairs(rows) do
      local r, g, b = classColor(row.char.class)
      layers[i] = { char = row.char, r = r, g = g, b = b }
    end
  elseif stackByMode(cfg) then
    for _, mode in ipairs(TB.MODES) do
      if not cfg.hidden[mode] then
        local c = MODE_COLOR[mode]
        layers[#layers + 1] = { mode = mode, r = c[1], g = c[2], b = c[3] }
      end
    end
  else
    local char = scopeChar(cfg.scope)
    if char then
      local r, g, b = classColor(char.class)
      layers[1] = { char = char, r = r, g = g, b = b }
    end
  end
  return layers
end

local function layerAmount(layer, b, kind)
  if layer.mode then return b.record and b.record.yards[layer.mode] or 0 end
  return valueOf(layer.char[kind][b.key])
end

local function showBarTooltip(bar)
  local b = bar.info
  if not b then return end
  GameTooltip:SetOwner(bar, "ANCHOR_TOP")
  GameTooltip:AddLine(b.title)
  local r = b.record
  if not r then
    GameTooltip:AddLine(b.future and "Still to come" or "No travel recorded", 0.6, 0.6, 0.6)
  else
    GameTooltip:AddDoubleLine("Steps", TB.Grouped(r.steps), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Jumps", TB.Grouped(r.jumps), 1, 1, 1, 1, 1, 1)
    if r.mountJumps then
      GameTooltip:AddDoubleLine("Mount jumps", TB.Grouped(r.mountJumps), 1, 1, 1, 1, 1, 1)
    end
    for _, mode in ipairs(TB.MODES) do
      local yards = r.yards[mode]
      if yards and yards > 0 then
        -- Modes switched off in the legend stay listed, greyed, so their numbers are at hand.
        if TB.db.chart.hidden[mode] then
          GameTooltip:AddDoubleLine(TB.MODE_LABEL[mode], TB.Distance(yards), 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
        else
          local c = MODE_COLOR[mode]
          GameTooltip:AddDoubleLine(TB.MODE_LABEL[mode], TB.Distance(yards), c[1], c[2], c[3], 1, 1, 1)
        end
        if mode == "taxi" and r.flights then
          GameTooltip:AddDoubleLine("   Fares", TB.FlightsText(r.flights, r.spent), 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
        end
      end
    end
    if TB.db.chart.scope == "account" then
      local rows = rankCharacters({ b.key })
      if #rows > 1 then
        GameTooltip:AddLine(" ")
        for i = 1, math.min(#rows, TOP_CONTRIBUTORS) do
          local row = rows[i]
          local r, g, bl = classColor(row.char.class)
          GameTooltip:AddDoubleLine(shortName(row.char), formatValue(row.total), r, g, bl, 1, 1, 1)
        end
        if #rows > TOP_CONTRIBUTORS then
          GameTooltip:AddLine(("+%d more"):format(#rows - TOP_CONTRIBUTORS), 0.6, 0.6, 0.6)
        end
      end
    end
  end
  GameTooltip:Show()
end

-- Hovering a name or a bar segment focuses that character: their segments stay lit in
-- every bar, everyone else's dim, and their name in the list lights up.
local function focusable(rows, char)
  for _, row in ipairs(rows) do
    if row.char == char then return true end
  end
end

local function applyFocus()
  local focus = win.focus
  for _, bar in ipairs(win.bars) do
    for s = 1, bar.shown or 0 do
      local seg = bar.segments[s]
      local alpha = seg.today and 1 or 0.85
      if focus and seg.char and seg.char ~= focus then alpha = DIMMED end
      seg:SetAlpha(alpha)
    end
  end
  for _, line in ipairs(win.rows) do
    if focus and line.char == focus then line:LockHighlight() else line:UnlockHighlight() end
  end
end

local function setFocus(char)
  if win.focus ~= char then
    win.focus = char
    applyFocus()
  end
end

-- Lays the segments out, at full height or, `elapsed` seconds into the grow-in, at a
-- share of it that ripples left to right.
local function placeSegments(elapsed)
  for i, bar in ipairs(win.bars) do
    local k = 1
    if elapsed then
      k = math.min(1, math.max(0, (elapsed - (i - 1) * GROW_STAGGER) / GROW_TIME))
      k = 1 - (1 - k) ^ 3  -- ease out
    end
    for s = 1, bar.shown or 0 do
      local seg = bar.segments[s]
      seg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, seg.y0 * k)
      seg:SetHeight(math.max(0.01, seg.h * k))
    end
  end
end

local function growStep()
  local elapsed = GetTime() - win.growStart
  if elapsed >= GROW_TIME + MAX_BARS * GROW_STAGGER then
    win:SetScript("OnUpdate", nil)
    win.growStart = nil
    elapsed = nil
  end
  placeSegments(elapsed)
end

local render

-- Redraw and let the bars grow in; used when the window opens or the view changes.
local function renderGrow()
  win.growStart = GetTime()
  win:SetScript("OnUpdate", growStep)
  render()
end

function render()
  local cfg = TB.db.chart
  local bars, title = periodBars(cfg.view, cfg.scope)

  win.period:SetText(title)
  win.next:SetEnabled(offset < 0)
  for view, b in pairs(win.viewButtons) do
    if view == cfg.view then b:LockHighlight() else b:UnlockHighlight() end
  end
  local scope = cfg.scope
  if TB.db.chars[scope] == TB.char then scope = "char" end
  win.metric:Select(cfg.metric)
  win.stack:Select(cfg.stack)
  win.stack:SetShown(cfg.metric == "distance" and cfg.scope == "account")
  win.scope:Select(scope)

  local peak, total, active, best = 0, 0, 0, nil
  local present = win.presentModes
  wipe(present)
  for _, b in ipairs(bars) do
    local v = valueOf(b.record)
    peak = math.max(peak, v)
    total = total + v
    if v > 0 then active = active + 1 end
    if v > 0 and (not best or v > valueOf(best.record)) then best = b end
    if b.record then
      for mode, yards in pairs(b.record.yards) do
        if yards > 0 then present[mode] = true end
      end
    end
  end

  -- Pick a tidy axis top in the units shown (2 km, not 2,000 yd = 1.83 km).
  local top
  if cfg.metric == "distance" then
    top = niceCeiling(peak / TB.YardsPerUnit()) * TB.YardsPerUnit()
  else
    top = niceCeiling(peak)
  end
  win.axisTop:SetText(axisLabel(top))
  win.axisMid:SetText(axisLabel(top / 2))

  -- Character ranking for the period; it also orders the stacked segments.
  local keys = {}
  for i, b in ipairs(bars) do keys[i] = b.key end
  local rows = rankCharacters(keys)
  local layers = chartLayers(cfg, rows, win.layers)
  local kind = barKind()

  local px = PixelUtil.GetPixelToUIUnitFactor() / win.plot:GetEffectiveScale()  -- one screen pixel
  local slot = CHART_W / #bars
  local width = math.max(4, slot * 0.7)
  for i = 1, MAX_BARS do
    local bar, b = win.bars[i], bars[i]
    if b then
      bar.info = b
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", win.plot, "BOTTOMLEFT", (i - 1) * slot + (slot - width) / 2, 0)
      bar:SetSize(width, CHART_H)
      bar.label:SetText(b.label)
      bar.label:SetTextColor(b.today and 1 or 0.7, b.today and 0.82 or 0.7, b.today and 0 or 0.7)

      -- One segment per layer, bottom up, with a one-pixel gap between neighbours so the
      -- stack reads as separate characters (or modes). Edges are snapped to whole screen
      -- pixels, or the gaps render one or two pixels wide depending on where they land.
      local y, shown, below = 0, 0, nil
      for _, layer in ipairs(layers) do
        local h = layerAmount(layer, b, kind) / top * CHART_H
        local bottom, topEdge = math.floor(y / px + 0.5), math.floor((y + h) / px + 0.5)
        if topEdge > bottom then
          shown = shown + 1
          local seg = bar.segments[shown]
          if not seg then
            seg = bar:CreateTexture(nil, "ARTWORK")
            bar.segments[shown] = seg
          end
          seg:SetColorTexture(layer.r, layer.g, layer.b, 1)
          seg:SetWidth(width)
          -- Only the all-characters stack has other characters to dim.
          seg.y0, seg.h, seg.today = bottom * px, (topEdge - bottom) * px, b.today
          seg.char = cfg.scope == "account" and layer.char or nil
          seg:Show()
          if below and below.h > 2 * px then below.h = below.h - px end
          below = seg
        end
        y = y + h
      end
      bar.shown = shown
      for s = shown + 1, #bar.segments do bar.segments[s]:Hide() end
      bar:Show()
    else
      bar.info = nil
      bar.shown = 0
      bar:Hide()
    end
  end

  -- Averages only count days (or months) with travel, so a fresh install isn't diluted.
  local unit = cfg.view == "year" and "month" or "day"
  local summary = ("Total %s   ·   Average %s per active %s"):format(
    formatValue(total), formatValue(active > 0 and total / active or 0), unit)
  if best then
    summary = summary .. ("   ·   Best: %s (%s)"):format(best.short, formatValue(valueOf(best.record)))
  end
  win.summary:SetText(summary)

  -- The legend doubles as the distance filter. It lists the modes that appear in this
  -- period, plus any switched off, so a hidden mode can always be brought back.
  local x, y = 0, 0
  for _, mode in ipairs(TB.MODES) do
    local entry = win.legend[mode]
    if cfg.metric == "distance" and (present[mode] or cfg.hidden[mode]) then
      local w = entry:GetWidth()
      if x > 0 and x + w > CHART_W then x, y = 0, y - LEGEND_ROW end
      entry:SetPoint("TOPLEFT", win.plot, "BOTTOMLEFT", x, -20 + y)
      x = x + w + LEGEND_GAP
      local off = cfg.hidden[mode]
      local c = MODE_COLOR[mode]
      entry.swatch:SetColorTexture(c[1], c[2], c[3], off and 0.15 or 1)
      entry.text:SetTextColor(off and 0.45 or 1, off and 0.45 or 1, off and 0.45 or 1)
      entry:Show()
    else
      entry:Hide()
    end
  end
  -- Point out that the legend is clickable until the filter has been used once. The note
  -- flows after the last entry like one more item, wrapping if the row is full.
  local hint = win.legendHint
  local showHint = cfg.metric == "distance" and not cfg.filterUsed
  if showHint then
    if x > 0 and x + hint:GetStringWidth() > CHART_W then x, y = 0, y - LEGEND_ROW end
    hint:SetPoint("TOPLEFT", win.plot, "BOTTOMLEFT", x, -21 + y)
  end
  hint:SetShown(showHint)

  local leader = rows[1] and rows[1].total or 1
  for i = 1, MAX_ROWS do
    local line, row = win.rows[i], rows[i]
    if row then
      line.guid, line.char = row.guid, row.char
      local r, g, b = classColor(row.char.class)
      line.name:SetText(shortName(row.char))
      line.name:SetTextColor(r, g, b)
      line.value:SetText(formatValue(row.total))
      line.fill:SetColorTexture(r, g, b, 0.9)
      line.fill:SetWidth(math.max(1, (LIST_W - 8) * row.total / leader))
      local selected = cfg.scope == row.guid or (cfg.scope == "char" and row.char == TB.char)
      line.marker:SetShown(selected)
      line.selectedBg:SetShown(selected)
      line:Show()
    else
      line.guid, line.char = nil, nil
      line:Hide()
    end
  end

  if win.focus and not focusable(rows, win.focus) then win.focus = nil end
  placeSegments(win.growStart and GetTime() - win.growStart)
  applyFocus()

  -- An open bar tooltip is rebuilt with the same data, so it never disagrees with the list.
  for i = 1, #bars do
    if GameTooltip:IsOwned(win.bars[i]) then showBarTooltip(win.bars[i]) end
  end
  if #rows == 0 then
    win.listNote:SetText("No travel in this period.")
  elseif #rows > MAX_ROWS then
    win.listNote:SetText(("+%d more"):format(#rows - MAX_ROWS))
  else
    win.listNote:SetText("")
  end
end

-- Focuses the character whose segment is under the cursor while a bar is hovered.
local function trackSegment(bar)
  local _, y = GetCursorPosition()
  y = y / bar:GetEffectiveScale() - bar:GetBottom()
  local found
  for s = 1, bar.shown do
    local seg = bar.segments[s]
    if y >= seg.y0 and y < seg.y0 + seg.h + 1 then found = seg.char end
  end
  setFocus(found)
end

local function button(text, width, onClick)
  local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- Two or more buttons side by side choosing one value of TB.db.chart[field], the chosen
-- one lit like the view buttons. `options` = { { value, label, width }, ... }; the group
-- is anchored by its right edge.
local function segmented(field, options)
  local group = CreateFrame("Frame", nil, win)
  group:SetHeight(22)
  group.buttons = {}
  local x = 0
  for i = #options, 1, -1 do
    local value, label, width = options[i][1], options[i][2], options[i][3]
    local b = button(label, width, function()
      TB.db.chart[field] = value
      renderGrow()
    end)
    b:SetParent(group)
    b:SetPoint("TOPRIGHT", group, "TOPRIGHT", -x, 0)
    x = x + width + 1
    group.buttons[value] = b
  end
  group:SetWidth(x - 1)
  function group:Select(chosen)
    for value, b in pairs(self.buttons) do
      if value == chosen then b:LockHighlight() else b:UnlockHighlight() end
    end
  end
  return group
end

-- Draws the History page into its pane of the Trailblazer window.
local function build(pane)
  win = CreateFrame("Frame", nil, pane)
  win:SetAllPoints()

  -- View, metric and scope controls.
  win.viewButtons = {}
  local prevButton
  for _, view in ipairs({ "week", "month", "year" }) do
    local b = button(view:gsub("^%l", string.upper), 64, function()
      TB.db.chart.view, offset = view, 0
      renderGrow()
    end)
    if prevButton then b:SetPoint("LEFT", prevButton, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 14, -32) end
    win.viewButtons[view] = b
    prevButton = b
  end

  -- Each pair shows both choices with the active one lit.
  win.scope = segmented("scope", { { "char", "Mine", 56 }, { "account", "All", 48 } })
  win.scope:SetPoint("TOPRIGHT", -14, -32)
  win.metric = segmented("metric", { { "steps", "Steps", 60 }, { "distance", "Distance", 80 } })
  win.metric:SetPoint("TOPRIGHT", win.scope, "TOPLEFT", -10, 0)
  win.stack = segmented("stack", { { "char", "Characters", 90 }, { "mode", "Travel", 64 } })
  win.stack:SetPoint("TOPRIGHT", win.metric, "TOPLEFT", -10, 0)

  -- Plot area, period navigation above it, and a baseline, midline and top line with
  -- axis labels.
  win.plot = CreateFrame("Frame", nil, win)
  win.plot:SetSize(CHART_W, CHART_H)
  win.plot:SetPoint("TOPLEFT", 60, -96)

  win.prev = button("<", 26, function() offset = offset - 1; renderGrow() end)
  win.prev:SetPoint("TOPLEFT", 14, -62)
  win.next = button(">", 26, function() offset = math.min(0, offset + 1); renderGrow() end)
  win.next:SetPoint("BOTTOMRIGHT", win.plot, "TOPRIGHT", 0, 12)
  win.period = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  win.period:SetPoint("BOTTOM", win.plot, "TOP", 0, 16)
  for _, frac in ipairs({ 0, 0.5, 1 }) do
    local line = win.plot:CreateTexture(nil, "BACKGROUND")
    line:SetColorTexture(1, 1, 1, frac == 0 and 0.35 or 0.1)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, frac * CHART_H)
    line:SetPoint("BOTTOMRIGHT", 0, frac * CHART_H)
  end
  win.axisTop = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.axisTop:SetPoint("RIGHT", win.plot, "TOPLEFT", -4, 0)
  win.axisMid = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.axisMid:SetPoint("RIGHT", win.plot, "LEFT", -4, 0)

  win.bars = {}
  for i = 1, MAX_BARS do
    local bar = CreateFrame("Frame", nil, win.plot)
    bar:EnableMouse(true)
    -- Redraw before showing the tooltip so the list and tooltip read the same moment.
    bar:SetScript("OnEnter", function(self)
      render()
      showBarTooltip(self)
      self:SetScript("OnUpdate", trackSegment)
    end)
    bar:SetScript("OnLeave", function(self)
      self:SetScript("OnUpdate", nil)
      GameTooltip_Hide()
      setFocus(nil)
    end)
    bar.segments = {}
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("TOP", bar, "BOTTOM", 0, -3)
    win.bars[i] = bar
  end

  -- Legend entries toggle their travel mode in the distance views; shift-click shows
  -- only that mode, or everything again if it already was the only one.
  win.legend, win.presentModes, win.layers = {}, {}, {}
  for _, mode in ipairs(TB.MODES) do
    local entry = CreateFrame("Button", nil, win)
    entry.swatch = entry:CreateTexture(nil, "ARTWORK")
    entry.swatch:SetSize(10, 10)
    entry.swatch:SetPoint("LEFT")
    entry.text = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    entry.text:SetPoint("LEFT", entry.swatch, "RIGHT", 4, 0)
    entry.text:SetText(TB.MODE_LABEL[mode])
    entry:SetSize(14 + entry.text:GetStringWidth(), 14)
    entry:SetScript("OnClick", function(self)
      local hidden = TB.db.chart.hidden
      if IsShiftKeyDown() then
        local solo = not hidden[mode]
        for _, other in ipairs(TB.MODES) do
          if other ~= mode and not hidden[other] then solo = false end
        end
        for _, other in ipairs(TB.MODES) do
          hidden[other] = not solo and other ~= mode or nil
        end
      else
        hidden[mode] = not hidden[mode] or nil
      end
      TB.db.chart.filterUsed = true
      render()
      if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    entry:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(TB.MODE_LABEL[mode])
      GameTooltip:AddLine(TB.db.chart.hidden[mode] and "Click to show" or "Click to hide", 1, 1, 1)
      GameTooltip:AddLine("Shift-click to show only this", 1, 1, 1)
      GameTooltip:Show()
    end)
    entry:SetScript("OnLeave", GameTooltip_Hide)
    win.legend[mode] = entry
  end
  win.legendHint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.legendHint:SetText("click to filter")

  win.summary = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.summary:SetPoint("BOTTOMLEFT", 16, 14)
  win.summary:SetWidth(CHART_W + 44)
  win.summary:SetJustifyH("LEFT")

  -- Character ranking beside the chart; click one to chart only them.
  local header = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("BOTTOMLEFT", win.plot, "TOPRIGHT", 24, 16)
  header:SetText("Characters")
  win.rows = {}
  for i = 1, MAX_ROWS do
    local line = CreateFrame("Button", nil, win)
    line:SetSize(LIST_W, ROW_H)
    line:SetPoint("TOPLEFT", win.plot, "TOPRIGHT", 24, -(i - 1) * (ROW_H + 2))
    -- A faint flat backdrop on hover, in white so it doesn't read as the gold selection.
    line.hover = line:CreateTexture(nil, "HIGHLIGHT")
    line.hover:SetAllPoints()
    line.hover:SetColorTexture(1, 1, 1, 0.08)
    -- Share of the leader as a thin bar under the name, so names stay readable in any
    -- class colour; the selected row gets a gold edge and a faint backdrop.
    line.fill = line:CreateTexture(nil, "ARTWORK")
    line.fill:SetPoint("BOTTOMLEFT", 8, 0)
    line.fill:SetHeight(2)
    line.selectedBg = line:CreateTexture(nil, "BACKGROUND")
    line.selectedBg:SetAllPoints()
    line.selectedBg:SetColorTexture(1, 0.82, 0, 0.12)
    line.marker = line:CreateTexture(nil, "ARTWORK")
    line.marker:SetPoint("TOPLEFT")
    line.marker:SetPoint("BOTTOMLEFT")
    line.marker:SetWidth(3)
    line.marker:SetColorTexture(1, 0.82, 0, 1)
    line.name = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.name:SetPoint("LEFT", 8, 1)
    line.value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.value:SetPoint("RIGHT", -4, 1)
    -- Long full names truncate before they reach the value.
    line.name:SetPoint("RIGHT", line.value, "LEFT", -6, 0)
    line.name:SetJustifyH("LEFT")
    line.name:SetWordWrap(false)
    line:SetScript("OnClick", function(self)
      local cfg = TB.db.chart
      local mine = TB.db.chars[self.guid] == TB.char
      local selected = cfg.scope == self.guid or (cfg.scope == "char" and mine)
      cfg.scope = selected and "account" or (mine and "char" or self.guid)
      renderGrow()
    end)
    line:SetScript("OnEnter", function(self) setFocus(self.char) end)
    line:SetScript("OnLeave", function() setFocus(nil) end)
    win.rows[i] = line
  end
  win.listNote = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.listNote:SetPoint("TOPLEFT", win.plot, "TOPRIGHT", 28, -MAX_ROWS * (ROW_H + 2) - 4)

  win:SetScript("OnShow", function()
    offset = 0
    win.focus = nil
    renderGrow()
  end)
end

TB.Window.Register("history", "History", function(pane)
  TB.db.chart = TB.db.chart or {}
  -- First open: this month's distance for all characters, stacked by travel mode.
  TB.db.chart.view = TB.db.chart.view or "month"
  TB.db.chart.metric = TB.db.chart.metric or "distance"
  TB.db.chart.scope = TB.db.chart.scope or "account"
  TB.db.chart.stack = TB.db.chart.stack or "mode"
  TB.db.chart.hidden = TB.db.chart.hidden or {}
  build(pane)
end)

function HistoryPage.Open()
  TB.Window.Open("history")
end

function HistoryPage.Toggle()
  TB.Window.Toggle("history")
end

-- Keeps an open window current while travelling, throttled since a redraw makes garbage.
-- A skipped update schedules one trailing redraw, so the window settles on the final
-- numbers after movement stops.
local LIVE_EVERY = 0.5
local renderedAt, trailing = 0, false

function HistoryPage.Refresh()
  if not (win and win:IsVisible() and offset == 0) then return end
  local wait = LIVE_EVERY - (GetTime() - renderedAt)
  if wait > 0 then
    if not trailing then
      trailing = true
      C_Timer.After(wait, function()
        trailing = false
        HistoryPage.Refresh()
      end)
    end
    return
  end
  renderedAt = GetTime()
  render()
end
