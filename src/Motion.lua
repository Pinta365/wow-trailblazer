local _, TB = ...

-- The motion engine: samples position (or speed, where position is hidden) a few times a
-- second while something moves us, sorts the travel into a mode (on foot, mounted,
-- swimming, a ship, a flight path...) and, on foot, into a gait and a step count. It
-- sleeps while we stand still, so idling costs nothing.
local Motion = {}
TB.Motion = Motion

local SAMPLE_EVERY = 0.2   -- seconds between position samples while awake
local TELEPORT_SPEED = 80  -- yd/s; faster than anything a player moves on their own
local JITTER = 0.01        -- yd; ignore sub-centimetre wobble
local WALK_FRACTION = 0.6  -- below this share of run speed, a forward move is a walk
local WALK_BACK_FRACTION = 0.5  -- the same for a backward move
local SIDE_COSINE = 0.5    -- |cos| under this between facing and travel = sidestep
local CARRIED_MARGIN = 2   -- yd/s; moving this much faster than our own speed = on a boat
-- Share of full speed that only moving backward reaches (backpedal ~0.64 of run speed,
-- swimming backward ~0.53 of swim speed; walking is ~0.36).
local BACKPEDAL_BAND = { 0.4, 0.8 }
local WATCH_EVERY = 1      -- seconds between idle checks for being carried
local SETTLE_TIME = 2      -- seconds after a taxi or vehicle ride whose drift is still that ride
local FARE_WAIT = 30       -- seconds a picked flight's fare waits for the flight to start

local sqrt, cos, sin, abs = math.sqrt, math.cos, math.sin, math.abs
local isSecret = issecretvalue or function() return false end

-- Last good fix. UnitPosition's first value grows northward, the second westward;
-- GetPlayerFacing is 0 at north and grows counter-clockwise (toward west).
local fixNorth, fixWest, fixArea
local riding = false  -- on a boat, zeppelin or tram at the last sample
local wasGhost = false
local lastSpeed       -- our own speed at the last sample
local rideMode, rideEnds = nil, 0  -- the last taxi or vehicle ride, and when it ended
local fare, fareAt    -- the flight just picked on the flight map, and when
local lastRunSpeed = BASE_MOVEMENT_SPEED or 7
local lastSwimSpeed = 4.72
local pending = 0
local driver = CreateFrame("Frame")
driver:Hide()

-- Live readout for /trailblazer debug.
Motion.probe = { source = "-", mode = "idle", gait = "-", speed = 0, moved = 0, stride = 0 }

-- While calibrating, measured on-foot yards are tallied per gait here.
Motion.trial = nil

local function readFix()
  local north, west, _, area = UnitPosition("player")
  if north == nil or isSecret(north) or isSecret(west) or isSecret(area) then return end
  return north, west, area
end

local function readSpeed()
  local now, run, _, swim = GetUnitSpeed("player")
  if now == nil or isSecret(now) or isSecret(run) or isSecret(swim) then return end
  return now, run, swim
end

local function readFacing()
  local f = GetPlayerFacing()
  if f == nil or isSecret(f) then return end
  return f
end

-- Animal forms: druid cat, travel, aquatic, bear, dire bear and flight, and shaman Ghost
-- Wolf. Moonkin walks upright, so it counts steps.
local TRAVEL_FORMS = { [1] = true, [3] = true, [4] = true, [5] = true, [8] = true,
  [16] = true, [27] = true, [29] = true }

local function shapeshifted()
  local form = GetShapeshiftFormID()
  return form and not isSecret(form) and TRAVEL_FORMS[form]
end

local function currentMode()
  -- Corpse runs have no steps: ghost speed would inflate them, and wisps have no feet.
  if UnitIsGhost("player") then return "ghost" end
  if UnitOnTaxi("player") then return "taxi" end
  if UnitInVehicle("player") then return "vehicle" end
  if IsSwimming() then return "swim" end
  if IsMounted() then return "mount" end
  if shapeshifted() then return "shapeshift" end
  if IsFalling() then return "air" end
  return "foot"
end

local function onTaxiOrVehicle()
  return UnitOnTaxi("player") or UnitInVehicle("player")
end

-- Something other than our own legs is moving us, so the sampler should stay awake.
local function beingCarried()
  return riding or onTaxiOrVehicle()
end

-- Travel direction relative to where the character faces: "ahead", "back" or "side".
-- Without a position delta or facing there is no direction; assume ahead.
local function heading(dNorth, dWest, dist)
  local facing = dNorth and readFacing()
  if not facing then return "ahead" end
  local along = (dNorth * cos(facing) + dWest * sin(facing)) / dist
  if along < -SIDE_COSINE then return "back" end
  if abs(along) < SIDE_COSINE then return "side" end
  return "ahead"
end

-- Direction from speed alone, for when no position delta shows it (on a ship, or in a
-- dungeon where coordinates are hidden): only a backpedal moves at backpedal speed, so
-- everything else counts as ahead. Strafing moves at run speed and can't be told apart.
local function directionFromSpeed(speed)
  local share = speed / (IsSwimming() and lastSwimSpeed or lastRunSpeed)
  return share >= BACKPEDAL_BAND[1] and share < BACKPEDAL_BAND[2] and "back" or "ahead"
end

local SWIM_STYLE = { ahead = "swimAhead", back = "swimBack", side = "swimSide" }

-- Returns the gait to file the travel under, and the gait whose stride the legs use.
-- Strafing is its own category but steps like a run or a walk at the same speed.
local function pickGait(dir, speed, runSpeed)
  if dir == "back" then
    local pace = speed < runSpeed * WALK_BACK_FRACTION and "walkBack" or "back"
    return pace, pace
  end
  local pace = speed < runSpeed * WALK_FRACTION and "walk" or "run"
  if dir == "side" then return "strafe", pace end
  return pace, pace
end

local function rebase()
  fixNorth, fixWest, fixArea = readFix()
end

-- `settling` is the last partial interval after we stopped: the speed reads 0 by then,
-- though we covered that ground moving, so the previous sample's speed stands in.
local function sample(dt, settling)
  local probe = Motion.probe
  local speedNow, runSpeed, swimSpeed = readSpeed()
  -- The speed is read at the end of the interval; if we slowed down during it (leaving a
  -- form, dismounting, Sprint ending) the faster pace covered most of it.
  local fastest = speedNow and math.max(speedNow, lastSpeed or 0)
  if settling and speedNow then speedNow = lastSpeed or speedNow end
  lastSpeed = speedNow
  if runSpeed and runSpeed > 0 then lastRunSpeed = runSpeed end
  if swimSpeed and swimSpeed > 0 then lastSwimSpeed = swimSpeed end

  local dist, dNorth, dWest, guessed = 0, nil, nil, false
  local north, west, area = readFix()

  if north then
    if area and area == fixArea then
      dNorth, dWest = north - fixNorth, west - fixWest
      dist = sqrt(dNorth * dNorth + dWest * dWest)
      if dist / dt > TELEPORT_SPEED then dist = 0 end
    end
    fixNorth, fixWest, fixArea = north, west, area
    probe.source = "position"
  else
    -- No coordinates (likely inside an instance): fall back to speed, then to a guess.
    fixNorth, fixWest, fixArea = nil, nil, nil
    if speedNow then
      dist = speedNow * dt
      probe.source = "speed"
    else
      dist, guessed = lastRunSpeed * dt, true
      probe.source = "estimate"
    end
  end

  probe.speed = speedNow or dist / dt
  probe.moved = dist / dt

  -- Releasing or reviving can snap our position; that instant isn't travel.
  local ghost = UnitIsGhost("player")
  if ghost ~= wasGhost then
    wasGhost = ghost
    return
  end

  -- Ships (boats, zeppelins, trams) aren't taxis or vehicles to the game. GetUnitSpeed
  -- reports only our own movement, so a position moving clearly faster than that is a ship
  -- carrying us; once aboard, any drift while we stand still is too. Not mid-air
  -- (knockbacks and falls) and not as a ghost (its speed can lack the ghost bonus).
  local carried, dir = 0, nil
  if dNorth and speedNow and not onTaxiOrVehicle() and not ghost then
    local own = speedNow * dt
    local boarding = not riding and not IsFalling()
    local landing = GetTime() < rideEnds and speedNow == 0  -- a flight path setting us down
    if landing or (riding or boarding) and (dist - fastest * dt > CARRIED_MARGIN * dt
        or (riding and speedNow == 0)) then
      -- The delta is mostly the ship, so it can't tell which way we walk. The ship's share
      -- is the delta minus our own movement along that facing.
      dir = directionFromSpeed(speedNow)
      local facing = readFacing() or 0
      local sign = dir == "back" and -1 or 1
      local shipNorth = dNorth - sign * own * cos(facing)
      local shipWest = dWest - sign * own * sin(facing)
      carried, dist = sqrt(shipNorth * shipNorth + shipWest * shipWest), own
    end
  end
  riding = carried >= JITTER
  -- Drift just after a flight path or vehicle ends belongs to that ride, not a ship.
  local carriedMode = GetTime() < rideEnds and rideMode or "transport"
  if riding then TB.Log(carriedMode, nil, carried, 0) end

  if dist < JITTER then
    if riding then
      probe.mode, probe.gait, probe.stride = carriedMode, "-", 0
      TB.Panel.Refresh()
      TB.HistoryPage.Refresh()
    end
    return
  end

  local mode = currentMode()
  if mode == "taxi" or mode == "vehicle" then
    rideMode, rideEnds = mode, GetTime() + SETTLE_TIME
    lastSpeed = nil  -- the ride's speed, not ours
  end
  -- The fare is only paid once we're actually in the air.
  if mode == "taxi" and fare then
    if GetTime() - fareAt < FARE_WAIT then TB.LogFlight(fare) end
    fare = nil
  end
  local steps, gait = 0, nil
  probe.mode, probe.gait, probe.stride = mode, "-", 0
  if not dir then
    dir = dNorth and heading(dNorth, dWest, dist) or directionFromSpeed(probe.speed)
  end
  if mode == "foot" then
    local pace
    gait, pace = pickGait(dir, probe.speed, lastRunSpeed)
    local stride = TB.Strides.Length(pace)
    steps = dist / stride
    probe.gait, probe.stride = gait, stride
    if Motion.trial and not guessed and not riding then
      Motion.trial[pace] = (Motion.trial[pace] or 0) + dist
    end
  elseif mode == "swim" then
    gait = SWIM_STYLE[dir]
    probe.gait = gait
  end

  TB.Log(mode, gait, dist, steps, guessed)
  TB.Panel.Refresh()
  TB.HistoryPage.Refresh()
end

driver:SetScript("OnUpdate", function(_, elapsed)
  pending = pending + elapsed
  if pending < SAMPLE_EVERY then return end
  -- A long hitch (loading screen, alt-tab) is not travel time.
  if pending < 1 then sample(pending) else rebase() end
  pending = 0
  -- Backstop for missed stop events (e.g. a taxi landing): doze once nothing moves us.
  if not IsPlayerMoving() and not beingCarried() and not IsFalling() then
    driver:Hide()
    Motion.probe.mode, Motion.probe.gait = "idle", "-"
    TB.Panel.Refresh()
    TB.HistoryPage.Refresh()
  end
end)

local function wake()
  if driver:IsShown() then return end
  rebase()
  pending = 0
  driver:Show()
end

-- While asleep, glance at our position now and then: a ship can carry us off while we
-- stand still, and no movement event fires for that.
local watchNorth, watchWest, watchArea
local function watch()
  if driver:IsShown() then
    watchNorth = nil
    return
  end
  local north, west, area = readFix()
  if north and watchNorth and area == watchArea then
    local dNorth, dWest = north - watchNorth, west - watchWest
    local speed = sqrt(dNorth * dNorth + dWest * dWest) / WATCH_EVERY
    if speed > CARRIED_MARGIN and speed < TELEPORT_SPEED then
      watchNorth = nil
      wake()
      return
    end
  end
  watchNorth, watchWest, watchArea = north, west, area
end

-- Settle the last partial interval, then stop sampling unless something still moves us.
local function sleep()
  if not driver:IsShown() or IsPlayerMoving() or beingCarried() then return end
  if pending > 0 and pending < 1 then sample(pending, true) end
  lastSpeed = nil
  driver:Hide()
  Motion.probe.mode, Motion.probe.gait = "idle", "-"
  TB.Panel.Refresh()
  TB.HistoryPage.Refresh()
end

local events = {
  PLAYER_STARTED_MOVING = wake,
  PLAYER_STOPPED_MOVING = sleep,
  PLAYER_CONTROL_LOST   = function() if beingCarried() then wake() end end,
  PLAYER_CONTROL_GAINED = sleep,
  UNIT_ENTERED_VEHICLE  = wake,
  UNIT_EXITED_VEHICLE   = sleep,
  PLAYER_REGEN_ENABLED  = function() TB.Strides.ResolveBody() end,
  -- The barber can change sex without a relog.
  BARBER_SHOP_APPEARANCE_APPLIED = function()
    TB.Strides.ResolveBody()
    TB.History.Describe()
  end,
  PLAYER_ENTERING_WORLD = function()
    TB.Strides.ResolveBody()
    driver:Hide()
    riding = false
    if IsPlayerMoving() or beingCarried() then wake() end
  end,
}

function Motion.Start()
  local listener = CreateFrame("Frame")
  for event in pairs(events) do
    if event:find("VEHICLE") then
      listener:RegisterUnitEvent(event, "player")
    else
      listener:RegisterEvent(event)
    end
  end
  listener:SetScript("OnEvent", function(_, event) events[event]() end)
  C_Timer.NewTicker(WATCH_EVERY, watch)
  if IsPlayerMoving() or beingCarried() then wake() end

  -- Both flight map windows start a flight through TakeTaxiNode(slot).
  hooksecurefunc("TakeTaxiNode", function(slot)
    local cost = TaxiNodeCost(slot)
    if cost and not isSecret(cost) then fare, fareAt = cost, GetTime() end
  end)

  -- Jump presses count from solid ground, a ship's deck included; not mid-air, in water,
  -- or on a taxi or vehicle.
  if JumpOrAscendStart then
    hooksecurefunc("JumpOrAscendStart", function()
      if not IsFalling() and not IsSwimming() and not onTaxiOrVehicle() then
        TB.LogJump(IsMounted())
      end
    end)
  end
end
