-- Ground probe around a rebase or a terrain-follow commit (perf, 2026-10-28: at 158 mph the road turned
-- bumpy ~3 s after a rebase and the car crashed; the 1 s trace samples could not say why). Just before the change,
-- just after it, and every SAMPLE_S for WATCH_S after it, the ground is read at AHEAD_M along the car's heading,
-- relative to the car's own ground (so the readings compare across the rebase's change of frame), with the car's
-- height above the ground, its speed and climb rate, and the colliders made near the car (M.collider, from roads.lua).
-- Lines go to the server log through core (perf_log), tagged "probe".
-- After a rebase, every SCENE_S also the scene round the car (roads.sceneNear, trees.sceneNear: which tiles are ghosts
-- or the new anchor's, and whether their meshes are made), and every ghost released near the car (M.note): the user saw
-- the road turn to painted ground and the trees go for a few seconds after rebases, and a scan 15 s later found all fine.
local M = {}

M.AHEAD_M = { 0, 25, 50, 100, 200 }
M.WATCH_S = 10.0
M.SCENE_S = 0.5
M.SAMPLE_S = 0.25
M.NEAR_M = 150          -- colliders made this close to the car are listed
M.JUMP_M = 0.3          -- a reading this far off the one before the change is flagged (a step in the ground)

local active = nil      -- { kind, at, nextAt, before, lines, colliders }
local out = {}          -- lines waiting for core (M.take)

-- The ground at (x, y) seen from height z: ray(x, y, z) -> ground z or nil (core.groundRay's).
local function readings(veh, ray)
  local p = veh:getPosition()
  local d = veh:getDirectionVector()
  local len = math.sqrt(d.x * d.x + d.y * d.y)
  if len < 1e-3 then d, len = { x = 0, y = 1 }, 1 end
  local fx, fy = d.x / len, d.y / len
  local g0 = ray(p.x, p.y, p.z)
  local r = { agl = g0 and (p.z - g0) or nil, ahead = {} }
  for i, a in ipairs(M.AHEAD_M) do
    local g = ray(p.x + fx * a, p.y + fy * a, p.z)
    r.ahead[i] = (g and g0) and (g - g0) or false     -- (false: no ground there)
  end
  local v = veh:getVelocity()
  r.mph = math.sqrt(v.x * v.x + v.y * v.y) * 2.23694
  r.vz = v.z
  return r
end

local function fmt(r, ref)
  local parts = {}
  for i, a in ipairs(M.AHEAD_M) do
    local h = r.ahead[i]
    local s = h and string.format('%d:%+.2f', a, h) or string.format('%d:none', a)
    local b = ref and ref.ahead[i]
    if h and b and math.abs(h - b) >= M.JUMP_M then s = s .. '!' end
    if (h == false) ~= (b == false) and ref then s = s .. '!' end
    parts[#parts + 1] = s
  end
  return string.format('agl %s, %.0f mph, vz %+.1f, ground ahead (m: dz vs the car\'s) %s',
    r.agl and string.format('%.2f', r.agl) or 'none', r.mph, r.vz or 0, table.concat(parts, ' '))
end

-- Just before a change of the ground (kind 'rebase' or 'terrain'): what it was.
function M.before(kind, veh, ray)
  if not veh or not ray then return end
  local ok, r = pcall(readings, veh, ray)
  if not ok then return end
  active = { kind = kind, before = r, colliders = {}, sceneAt = -1 }
  out[#out + 1] = string.format('probe %s before: %s', kind, fmt(r))
end

-- Just after it (clock: core's st.clock), and the watch begins.
function M.after(clock, veh, ray)
  if not active or not veh or not ray then return end
  active.at, active.nextAt = clock, clock + M.SAMPLE_S
  local ok, r = pcall(readings, veh, ray)
  if ok then out[#out + 1] = string.format('probe %s after: %s', active.kind, fmt(r, active.before)) end
end

-- Every frame: a sample every SAMPLE_S while the watch runs.
function M.update(clock, veh, ray)
  if not active or not active.at then return end
  if clock - active.at > M.WATCH_S or not veh or not ray then
    if #active.colliders > 0 then
      out[#out + 1] = string.format('probe %s colliders near the car: %s', active.kind, table.concat(active.colliders, ', '))
    end
    active = nil
    return
  end
  active.now = clock
  if clock < active.nextAt then return end
  active.nextAt = clock + M.SAMPLE_S
  local ok, r = pcall(readings, veh, ray)
  if ok then
    out[#out + 1] = string.format('probe %s +%.2fs: %s', active.kind, clock - active.at, fmt(r, active.before))
  end
  if active.kind == 'rebase' and clock - active.sceneAt >= M.SCENE_S - 1e-6 then
    active.sceneAt = clock
    local p = veh:getPosition()
    for _, name in ipairs({ 'roads', 'trees' }) do
      local okS, s = pcall(function() return require('beamngEarth/' .. name).sceneNear(p.x, p.y) end)
      out[#out + 1] = string.format('probe %s +%.2fs %s: %s', active.kind, clock - active.at, name,
        okS and tostring(s) or ('error ' .. tostring(s)))
    end
  end
end

-- Something that happened near the car while the watch runs (a ghost released: roads.lua, trees.lua).
function M.note(text)
  if not active or not active.at then return end
  out[#out + 1] = string.format('probe %s +%.2fs: %s', active.kind, (active.now or active.at) - active.at, text)
end

-- A collider made (roads.lua): what, and its distance from the car (m).
function M.collider(what, dist)
  if not active or not active.at or not dist or dist > M.NEAR_M then return end
  active.colliders[#active.colliders + 1] = string.format('%s %.0f m at +%.2fs', tostring(what), dist,
    (active.now or active.at) - active.at)
end

function M.watching() return active ~= nil and active.at ~= nil end

-- The lines since the last call.
function M.take()
  local o = out
  out = {}
  return o
end

return M
