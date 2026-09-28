-- ForeverGlow.lua - WoW: Forever.
--
-- Animated glows for engine-driven displays. The engine's clips are anchored to Blizzard aura containers
-- and aura buttons. While an aura is shown there, every region anchored to them, however indirectly, has
-- SECRET anchoring: the client refuses SetPoint, ClearAllPoints and SetSize on it from addon code
-- ("Attempt to access forbidden object", found 2026-09-28 with Pixel Glow), and nothing may be re-parented
-- into the clips (WeakAuras' glow frame and LibCustomGlow's pooled frames are both refused, 2026-09-27).
-- So a glow here is CREATED in place, laid out once, and then MOVED BY THE CLIENT ALONE: every motion is
-- an animation (Path, FlipBook), never a script that lays textures out. Looks and motion follow
-- LibCustomGlow, which WeakAuras bundles, so the four WeakAuras glow types look the same: Button Glow,
-- Pixel Glow, Autocast Shine and Proc Glow (the looping part; the one-off start burst is left out).
--
-- Private.ForeverGlow.Start(holder, sub, w, h) starts the glow described by a WeakAuras glow sub-region on
-- holder (w by h, plain numbers) and returns true; Stop(holder) ends it.
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local G = {}
Private.ForeverGlow = G
if type(_G[AddonName]) == "table" then _G[AddonName].ForeverGlow = G end   -- reachable by the dev probes

local WHITE = "Interface\\BUTTONS\\WHITE8X8"
local EMPTY = "Interface\\AdventureMap\\BrokenIsles\\AM_29"
local ICON_ALERT = "Interface\\SpellActivationOverlay\\IconAlert"
local ANTS = "Interface\\SpellActivationOverlay\\IconAlertAnts"
local OUTER_TC = { 0.00781250, 0.50781250, 0.27734375, 0.52734375 }
local isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local SHINE = isRetail and "Interface\\Artifacts\\Artifacts" or "Interface\\ItemSocketingFrame\\UI-ItemSockets"
local SHINE_TC = isRetail and { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }
                           or { 0.3984375, 0.4453125, 0.40234375, 0.44921875 }
local DEFAULT_COLOR = { 0.95, 0.95, 0.32, 1 }
local SQRT2 = math.sqrt(2)

local function SetColor(tex, color, desaturate)
  if color then
    tex:SetDesaturated(desaturate and true or false)
    tex:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
  else
    tex:SetDesaturated(false)
    tex:SetVertexColor(1, 1, 1, 1)
  end
end

-- One child frame per glow type, created on first use inside the holder.
local function Part(holder, kind)
  holder.fgParts = holder.fgParts or {}
  local f = holder.fgParts[kind]
  if not f then
    f = CreateFrame("Frame", nil, holder)
    f:Hide()
    holder.fgParts[kind] = f
  end
  f:SetFrameLevel(holder:GetFrameLevel() + 1)
  return f
end

-- A repeating animation group owned by region, remembered on the part so Stop can end it.
local function Loop(part, region)
  local ag = region:CreateAnimationGroup()
  ag:SetLooping("REPEAT")
  part.loops = part.loops or {}
  part.loops[#part.loops + 1] = ag
  return ag
end

local function StopLoops(part)
  for _, ag in ipairs(part.loops or {}) do ag:Stop() end
end

local function HideAll(holder)
  for _, f in pairs(holder.fgParts or {}) do
    StopLoops(f)
    f:Hide()
  end
end

-- A Path animation that carries the region from its own position through the given corners (offsets
-- from that position) and back, one lap per `duration` seconds. The path is straight between its points,
-- so every corner is a point; the client shares the time out between the points, so each side is cut
-- into steps of nearly the same length for a steady speed.
local function RectPath(ag, duration, corners)
  local path = ag:CreateAnimation("Path")
  path:SetDuration(duration)
  pcall(path.SetCurveType, path, "NONE")
  pcall(path.SetSmoothing, path, "NONE")
  local lens, total, px, py = {}, 0, 0, 0
  for i, c in ipairs(corners) do
    lens[i] = math.abs(c[1] - px) + math.abs(c[2] - py)   -- the sides are axis-aligned
    total = total + lens[i]
    px, py = c[1], c[2]
  end
  local unit = math.max(4, total / 32)
  local order = 0
  px, py = 0, 0
  for i, c in ipairs(corners) do
    local steps = math.max(1, math.floor(lens[i] / unit + 0.5))
    for s = 1, steps do
      order = order + 1
      local cp = path:CreateControlPoint(nil, nil, order)
      cp:SetOffset(px + (c[1] - px) * s / steps, py + (c[2] - py) * s / steps)
    end
    px, py = c[1], c[2]
  end
  return path
end

-- Restarts region's lap: rebuilt when the rectangle or the lap time changed, else just replayed from
-- `offset` seconds into the lap.
local function PlayLap(part, region, sig, duration, corners, offset)
  local ag = region.loop
  if not ag then
    ag = Loop(part, region)
    region.loop = ag
  end
  ag:Stop()
  if region.sig ~= sig then
    pcall(ag.RemoveAnimations, ag)
    RectPath(ag, duration, corners)
    region.sig = sig
  end
  ag:Play(false, offset % duration)
end

---------------------------------------------------------------------------- Button Glow
-- The ants are a 256x256 sheet of 22 frames of 48x48, 5 per row (Blizzard's AnimateTexCoords parameters),
-- played as a FlipBook animation.
local ANTS_ROWS, ANTS_COLS, ANTS_FRAMES, ANTS_PX = 5, 5, 22, 48

local function StartButton(holder, sub, w, h)
  local f = Part(holder, "button")
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", -w * 0.2, h * 0.2)
  f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", w * 0.2, -h * 0.2)
  if not f.outer then
    f.outer = f:CreateTexture(nil, "ARTWORK")
    f.outer:SetTexture(ICON_ALERT)
    f.outer:SetTexCoord(OUTER_TC[1], OUTER_TC[2], OUTER_TC[3], OUTER_TC[4])
    f.outer:SetAllPoints(f)
    f.ants = f:CreateTexture(nil, "OVERLAY")
    f.ants:SetTexture(ANTS)
    f.ants:SetPoint("CENTER")
    f.antsLoop = Loop(f, f.ants)
    f.antsFlip = f.antsLoop:CreateAnimation("FlipBook")
    f.antsFlip:SetFlipBookRows(ANTS_ROWS)
    f.antsFlip:SetFlipBookColumns(ANTS_COLS)
    f.antsFlip:SetFlipBookFrames(ANTS_FRAMES)
    f.antsFlip:SetFlipBookFrameWidth(ANTS_PX)
    f.antsFlip:SetFlipBookFrameHeight(ANTS_PX)
  end
  f.ants:SetSize(w * 1.4 * 0.85, h * 1.4 * 0.85)
  local color = sub.useGlowColor and sub.glowColor or nil
  SetColor(f.outer, color, true)
  SetColor(f.ants, color, true)
  -- Blizzard's default advances one frame per 0.01 s; WA scales that by its frequency setting
  local freq = tonumber(sub.glowFrequency)
  local throttle = (freq and freq > 0) and (0.25 / freq * 0.01) or 0.01
  f.antsLoop:Stop()
  f.antsFlip:SetDuration(ANTS_FRAMES * throttle)
  f:Show()
  f.antsLoop:Play()
end

---------------------------------------------------------------------------- Pixel Glow
-- Each line is a square turned 45 degrees (a diamond) whose centre rides the middle of the border ring,
-- one lap per period, clockwise from the bottom left as in LibCustomGlow. The ring mask keeps only what
-- lies in the ring and the part clips what pokes out past the border, so what shows is a line of about
-- `length` along the ring that bends round the corners like LibCustomGlow's: the ring points within
-- length/2 of the centre, measured along the ring, are exactly the diamond's.
local function StartPixel(holder, sub, w, h)
  local f = Part(holder, "pixel")
  local n = tonumber(sub.glowLines) or 8
  if n < 1 then n = 8 end
  local freq = tonumber(sub.glowFrequency) or 0.25
  local period = (freq > 0 or freq < 0) and math.abs(1 / freq) or 4
  local length = tonumber(sub.glowLength) or math.floor((w + h) * (2 / n - 0.1))
  length = math.min(length, math.min(w, h))
  local th = tonumber(sub.glowThickness) or 1
  local xo, yo = tonumber(sub.glowXOffset) or 0, tonumber(sub.glowYOffset) or 0
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", -xo + 0.05, yo + 0.05)
  f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", xo, -yo + 0.05)
  f:SetClipsChildren(true)
  if not f.mask then
    f.mask = f:CreateMaskTexture()
    f.mask:SetTexture(EMPTY, "CLAMPTOWHITE", "CLAMPTOWHITE")
    f.lines = {}
  end
  f.mask:ClearAllPoints()
  f.mask:SetPoint("TOPLEFT", f, "TOPLEFT", th, -th)
  f.mask:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -th, th)
  local color = sub.useGlowColor and sub.glowColor or DEFAULT_COLOR
  -- the part spans the holder plus the offsets (see the anchors above)
  local W, H = w + 2 * xo, h + 2 * yo
  local side = length / SQRT2   -- the diamond's diagonal is the line length
  local corners = { { 0, H - th }, { W - th, H - th }, { W - th, 0 }, { 0, 0 } }
  local sig = table.concat({ W, H, th, period }, ":")
  for i = 1, math.max(n, #f.lines) do
    local line = f.lines[i]
    if i <= n then
      if not line then
        line = f:CreateTexture(nil, "ARTWORK", nil, 7)
        line:SetTexture(WHITE)
        line:SetRotation(math.pi / 4)
        line:AddMaskTexture(f.mask)
        f.lines[i] = line
      end
      line:ClearAllPoints()
      line:SetPoint("CENTER", f, "BOTTOMLEFT", th / 2, th / 2)
      line:SetSize(side, side)
      SetColor(line, color, false)
      line:Show()
      PlayLap(f, line, sig, period, corners, period * (i - 1) / n)
    elseif line then
      if line.loop then line.loop:Stop() end
      line:Hide()
    end
  end
  if sub.glowBorder then
    if not f.bg then
      f.mask2 = f:CreateMaskTexture()
      f.mask2:SetTexture(EMPTY, "CLAMPTOWHITE", "CLAMPTOWHITE")
      f.bg = f:CreateTexture(nil, "ARTWORK", nil, 6)
      f.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
      f.bg:SetAllPoints(f)
      f.bg:AddMaskTexture(f.mask2)
    end
    f.mask2:ClearAllPoints()
    f.mask2:SetPoint("TOPLEFT", f, "TOPLEFT", th + 1, -th - 1)
    f.mask2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -th - 1, th + 1)
    f.bg:Show()
  elseif f.bg then
    f.bg:Hide()
  end
  f:Show()
end

---------------------------------------------------------------------------- Autocast Shine
-- Four sizes of sparkle, n of each, circling the border: the bigger, the slower (one lap per period times
-- the size group), spread evenly round the lap, as in LibCustomGlow.
local SHINE_SIZES = { 7, 6, 5, 4 }

local function StartShine(holder, sub, w, h)
  local f = Part(holder, "shine")
  local n = tonumber(sub.glowLines) or 4
  if n < 1 then n = 4 end
  local freq = tonumber(sub.glowFrequency) or 0.125
  local period = (freq > 0 or freq < 0) and math.abs(1 / freq) or 8
  local scale = tonumber(sub.glowScale) or 1
  local xo, yo = tonumber(sub.glowXOffset) or 0, tonumber(sub.glowYOffset) or 0
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", -xo + 0.05, yo + 0.05)
  f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", xo, -yo + 0.05)
  f.dots = f.dots or {}
  local color = sub.useGlowColor and sub.glowColor or DEFAULT_COLOR
  local W, H = w + 2 * xo, h + 2 * yo
  local corners = { { 0, H }, { W, H }, { W, 0 }, { 0, 0 } }
  local sig = table.concat({ W, H, period }, ":")
  local total = n * 4
  for i = 1, math.max(total, #f.dots) do
    local dot = f.dots[i]
    if i <= total then
      if not dot then
        dot = f:CreateTexture(nil, "ARTWORK", nil, 7)
        dot:SetTexture(SHINE)
        dot:SetTexCoord(SHINE_TC[1], SHINE_TC[2], SHINE_TC[3], SHINE_TC[4])
        if not isRetail then dot:SetBlendMode("ADD") end
        f.dots[i] = dot
      end
      local k = math.floor((i - 1) / n) + 1   -- size group
      local size = SHINE_SIZES[k] * scale
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", f, "BOTTOMLEFT")
      dot:SetSize(size, size)
      SetColor(dot, color, true)
      dot:Show()
      local lap = period * k
      PlayLap(f, dot, sig, lap, corners, lap * ((i - 1) % n + 1) / n)
    elseif dot then
      if dot.loop then dot.loop:Stop() end
      dot:Hide()
    end
  end
  f:Show()
end

---------------------------------------------------------------------------- Proc Glow
local function StartProc(holder, sub, w, h)
  local f = Part(holder, "proc")
  local xo = (tonumber(sub.glowXOffset) or 0) + w * 0.2
  local yo = (tonumber(sub.glowYOffset) or 0) + h * 0.2
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", -xo, yo)
  f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", xo, -yo)
  if not f.tex then
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
    f.tex:SetAllPoints(f)
    f.procLoop = Loop(f, f.tex)
    f.flip = f.procLoop:CreateAnimation("FlipBook")
    f.flip:SetFlipBookRows(6)
    f.flip:SetFlipBookColumns(5)
    f.flip:SetFlipBookFrames(30)
    f.flip:SetFlipBookFrameWidth(0)
    f.flip:SetFlipBookFrameHeight(0)
  end
  f.procLoop:Stop()
  f.flip:SetDuration(tonumber(sub.glowDuration) or 1)
  SetColor(f.tex, sub.useGlowColor and sub.glowColor or nil, true)
  f:Show()
  f.procLoop:Play()
end

---------------------------------------------------------------------------- entry points
local STARTERS = { buttonOverlay = StartButton, Pixel = StartPixel, ACShine = StartShine, Proc = StartProc }

-- w, h: the holder's size, passed in because frames inside Blizzard's aura buttons answer GetSize()
-- with secret values in combat (the engine knows the display's plain size).
function G.Start(holder, sub, w, h)
  local start = STARTERS[sub and sub.glowType or "buttonOverlay"]
  if not start then return false end
  if not (w and h) then w, h = holder:GetSize() end
  if issecretvalue(w) or issecretvalue(h) or not (w > 0 and h > 0) then return false end
  HideAll(holder)
  holder:Show()
  start(holder, sub, w, h)
  return true
end

function G.Stop(holder)
  if not holder then return end
  HideAll(holder)
  holder:Hide()
end
