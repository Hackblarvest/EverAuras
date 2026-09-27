-- ForeverGlow.lua - WoW: Forever.
--
-- Animated glows for engine-driven displays. The engine's clips are anchored to Blizzard aura containers
-- and carry the UntrustedLayoutScriptExecution aspect, and no frame or texture may be re-parented into
-- them: WeakAuras' glow frame and LibCustomGlow's pooled frames are both refused (tested 2026-09-27).
-- Everything here is CREATED inside the frame it draws on and never moves. Textures and motion follow
-- LibCustomGlow, which WeakAuras bundles, so the four WeakAuras glow types look the same: Button Glow,
-- Pixel Glow, Autocast Shine and Proc Glow (the looping part; the one-off start burst is left out).
--
-- Private.ForeverGlow.Start(holder, sub) starts the glow described by a WeakAuras glow sub-region on
-- holder (a plain-sized frame) and returns true; Stop(holder) ends it.
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local G = {}
Private.ForeverGlow = G

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
local AnimateTexCoords = (TextureUtil and TextureUtil.AnimateTexCoords) or _G.AnimateTexCoords

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

local function HideAll(holder)
  for _, f in pairs(holder.fgParts or {}) do
    f:SetScript("OnUpdate", nil)
    if f.loop then f.loop:Stop() end
    f:Hide()
  end
end

---------------------------------------------------------------------------- Button Glow
local function ButtonUpdate(self, elapsed)
  if AnimateTexCoords then AnimateTexCoords(self.ants, 256, 256, 48, 48, 22, elapsed, self.throttle) end
end

local function StartButton(holder, sub)
  local f = Part(holder, "button")
  local w, h = holder:GetSize()
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
  end
  f.ants:SetSize(w * 1.4 * 0.85, h * 1.4 * 0.85)
  local color = sub.useGlowColor and sub.glowColor or nil
  SetColor(f.outer, color, true)
  SetColor(f.ants, color, true)
  local freq = tonumber(sub.glowFrequency)
  f.throttle = (freq and freq > 0) and (0.25 / freq * 0.01) or 0.01
  f:SetScript("OnUpdate", ButtonUpdate)
  f:Show()
end

---------------------------------------------------------------------------- Pixel Glow
-- Positions of a line travelling round the border, as in LibCustomGlow.
local function Calc1(progress, s, th, p)
  local c
  if progress > p[3] or progress < p[0] then c = 0
  elseif progress > p[2] then c = s - th - (progress - p[2]) / (p[3] - p[2]) * (s - th)
  elseif progress > p[1] then c = s - th
  else c = (progress - p[0]) / (p[1] - p[0]) * (s - th) end
  return math.floor(c + 0.5)
end

local function Calc2(progress, s, th, p)
  local c
  if progress > p[3] then c = s - th - (progress - p[3]) / (p[0] + 1 - p[3]) * (s - th)
  elseif progress > p[2] then c = s - th
  elseif progress > p[1] then c = (progress - p[1]) / (p[2] - p[1]) * (s - th)
  elseif progress > p[0] then c = 0
  else c = s - th - (progress + 1 - p[3]) / (p[0] + 1 - p[3]) * (s - th) end
  return math.floor(c + 0.5)
end

local function PixelUpdate(self, elapsed)
  local info = self.info
  self.timer = (self.timer + elapsed / info.period) % 1
  local w, h = self:GetSize()
  if w ~= info.width or h ~= info.height then
    local perimeter = 2 * (w + h)
    if not (perimeter > 0) then return end
    info.width, info.height = w, h
    local L = info.length / 2
    info.pTLx = { [0] = (h + L) / perimeter, [1] = (h + w + L) / perimeter, [2] = (2 * h + w - L) / perimeter, [3] = 1 - L / perimeter }
    info.pTLy = { [0] = (h - L) / perimeter, [1] = (h + w + L) / perimeter, [2] = (2 * h + w + L) / perimeter, [3] = 1 - L / perimeter }
    info.pBRx = { [0] = L / perimeter, [1] = (h - L) / perimeter, [2] = (h + w - L) / perimeter, [3] = (2 * h + w + L) / perimeter }
    info.pBRy = { [0] = L / perimeter, [1] = (h + L) / perimeter, [2] = (h + w - L) / perimeter, [3] = (2 * h + w - L) / perimeter }
  end
  local th = info.th
  for k, line in ipairs(self.lines) do
    if k > info.n then break end
    local p = (self.timer + info.step * (k - 1)) % 1
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", self, "TOPLEFT", Calc1(p, w, th, info.pTLx), -Calc2(p, h, th, info.pTLy))
    line:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", th + Calc2(p, w, th, info.pBRx), -h + Calc1(p, h, th, info.pBRy))
  end
end

local function StartPixel(holder, sub)
  local f = Part(holder, "pixel")
  local w, h = holder:GetSize()
  local n = tonumber(sub.glowLines) or 8
  if n < 1 then n = 8 end
  local freq = tonumber(sub.glowFrequency) or 0.25
  local period = (freq > 0 or freq < 0) and (1 / freq) or 4
  local length = tonumber(sub.glowLength) or math.floor((w + h) * (2 / n - 0.1))
  length = math.min(length, math.min(w, h))
  local th = tonumber(sub.glowThickness) or 1
  local xo, yo = tonumber(sub.glowXOffset) or 0, tonumber(sub.glowYOffset) or 0
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", -xo + 0.05, yo + 0.05)
  f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", xo, -yo + 0.05)
  if not f.mask then
    f.mask = f:CreateMaskTexture()
    f.mask:SetTexture(EMPTY, "CLAMPTOWHITE", "CLAMPTOWHITE")
    f.lines = {}
  end
  f.mask:ClearAllPoints()
  f.mask:SetPoint("TOPLEFT", f, "TOPLEFT", th, -th)
  f.mask:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -th, th)
  local color = sub.useGlowColor and sub.glowColor or DEFAULT_COLOR
  for i = 1, math.max(n, #f.lines) do
    local line = f.lines[i]
    if i <= n then
      if not line then
        line = f:CreateTexture(nil, "ARTWORK", nil, 7)
        line:SetTexture(WHITE)
        line:AddMaskTexture(f.mask)
        f.lines[i] = line
      end
      SetColor(line, color, false)
      line:Show()
    elseif line then
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
  f.timer = f.timer or 0
  f.info = { n = n, step = 1 / n, period = period, th = th, length = length }
  f:Show()
  PixelUpdate(f, 0)
  f:SetScript("OnUpdate", PixelUpdate)
end

---------------------------------------------------------------------------- Autocast Shine
local SHINE_SIZES = { 7, 6, 5, 4 }

local function ShineUpdate(self, elapsed)
  local info = self.info
  local w, h = self:GetSize()
  if w ~= info.width or h ~= info.height then
    if w * h == 0 then return end
    info.width, info.height = w, h
    info.perimeter = 2 * (w + h)
    info.bottomlim = h * 2 + w
    info.rightlim = h + w
    info.space = info.perimeter / info.n
  end
  local index = 0
  for k = 1, 4 do
    self.timer[k] = (self.timer[k] + elapsed / (info.period * k)) % 1
    for i = 1, info.n do
      index = index + 1
      local dot = self.dots[index]
      local pos = (info.space * i + info.perimeter * self.timer[k]) % info.perimeter
      dot:ClearAllPoints()
      if pos > info.bottomlim then
        dot:SetPoint("CENTER", self, "BOTTOMRIGHT", -pos + info.bottomlim, 0)
      elseif pos > info.rightlim then
        dot:SetPoint("CENTER", self, "TOPRIGHT", 0, -pos + info.rightlim)
      elseif pos > info.height then
        dot:SetPoint("CENTER", self, "TOPLEFT", pos - info.height, 0)
      else
        dot:SetPoint("CENTER", self, "BOTTOMLEFT", 0, pos)
      end
    end
  end
end

local function StartShine(holder, sub)
  local f = Part(holder, "shine")
  local n = tonumber(sub.glowLines) or 4
  if n < 1 then n = 4 end
  local freq = tonumber(sub.glowFrequency) or 0.125
  local period = (freq > 0 or freq < 0) and (1 / freq) or 8
  local scale = tonumber(sub.glowScale) or 1
  local xo, yo = tonumber(sub.glowXOffset) or 0, tonumber(sub.glowYOffset) or 0
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", -xo + 0.05, yo + 0.05)
  f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", xo, -yo + 0.05)
  f.dots = f.dots or {}
  local color = sub.useGlowColor and sub.glowColor or DEFAULT_COLOR
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
      local size = SHINE_SIZES[math.floor((i - 1) / n) + 1] * scale
      dot:SetSize(size, size)
      SetColor(dot, color, true)
      dot:Show()
    elseif dot then
      dot:Hide()
    end
  end
  f.timer = f.timer or { 0, 0, 0, 0 }
  f.info = { n = n, period = period }
  f:Show()
  ShineUpdate(f, 0)
  f:SetScript("OnUpdate", ShineUpdate)
end

---------------------------------------------------------------------------- Proc Glow
local function StartProc(holder, sub)
  local f = Part(holder, "proc")
  local w, h = holder:GetSize()
  local xo = (tonumber(sub.glowXOffset) or 0) + w * 0.2
  local yo = (tonumber(sub.glowYOffset) or 0) + h * 0.2
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", -xo, yo)
  f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", xo, -yo)
  if not f.tex then
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
    f.tex:SetAllPoints(f)
    f.ProcLoop = f.tex
    f.loop = f:CreateAnimationGroup()
    f.loop:SetLooping("REPEAT")
    f.flip = f.loop:CreateAnimation("FlipBook")
    f.flip:SetChildKey("ProcLoop")
    f.flip:SetOrder(0)
    f.flip:SetFlipBookRows(6)
    f.flip:SetFlipBookColumns(5)
    f.flip:SetFlipBookFrames(30)
    f.flip:SetFlipBookFrameWidth(0)
    f.flip:SetFlipBookFrameHeight(0)
  end
  f.flip:SetDuration(tonumber(sub.glowDuration) or 1)
  SetColor(f.tex, sub.useGlowColor and sub.glowColor or nil, true)
  f:Show()
  f.loop:Play()
end

---------------------------------------------------------------------------- entry points
local STARTERS = { buttonOverlay = StartButton, Pixel = StartPixel, ACShine = StartShine, Proc = StartProc }

function G.Start(holder, sub)
  local start = STARTERS[sub and sub.glowType or "buttonOverlay"]
  if not start then return false end
  local w, h = holder:GetSize()
  if issecretvalue(w) or issecretvalue(h) or not (w > 0 and h > 0) then return false end
  HideAll(holder)
  holder:Show()
  start(holder, sub)
  return true
end

function G.Stop(holder)
  if not holder then return end
  HideAll(holder)
  holder:Hide()
end
