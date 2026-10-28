-- luajit mod/tests/test_groundprobe.lua  (the ground probe round a rebase or a terrain-follow commit)
local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local P = require('beamngEarth/groundprobe')

-- a car at (x, 0, 10.5) heading +x at 70 m/s; the ground at height ground(x)
local car = { x = 0 }
local veh = {
  getPosition = function() return { x = car.x, y = 0, z = 10.5 } end,
  getDirectionVector = function() return { x = 1, y = 0, z = 0 } end,
  getVelocity = function() return { x = 70, y = 0, z = 0 } end,
}
local ground = function() return 10 end
local ray = function(x, y, z) return ground(x) end

T.check(#P.take() == 0 and not P.watching(), 'idle: nothing')
P.before('rebase', veh, ray)
local l = P.take()
T.check(#l == 1 and l[1]:find('probe rebase before: agl 0.50, 157 mph') ~= nil, 'before: the car and the ground ahead')
T.check(l[1]:find('100:%+0.00') ~= nil, 'flat ground ahead')

-- after the change the ground 100 m on is 0.8 m higher, and 200 m on there is none
ground = function(x) if x >= 200 then return nil elseif x >= 100 then return 10.8 end return 10 end
P.after(0, veh, ray)
l = P.take()
T.check(#l == 1 and l[1]:find('100:%+0.80!') ~= nil and l[1]:find('200:none!') ~= nil, 'after: the steps flagged')
T.check(l[1]:find('50:%+0.00!') == nil, 'unchanged readings not flagged')

P.collider('walk', 40)
P.collider('bldcol', 900)                   -- (too far: not listed)
P.update(0.1, veh, ray)
T.check(#P.take() == 0, 'no sample before SAMPLE_S')
P.update(0.3, veh, ray)
l = P.take()
T.check(#l == 1 and l[1]:find('probe rebase %+0.30s') ~= nil, 'a sample every SAMPLE_S')
P.update(P.WATCH_S + 1, veh, ray)
l = P.take()
T.check(#l == 1 and l[1]:find('colliders near the car: walk 40 m') ~= nil and l[1]:find('bldcol') == nil,
  'the watch ends with the colliders made near the car')
T.check(not P.watching(), 'and stops')
P.update(P.WATCH_S + 2, veh, ray)
T.check(#P.take() == 0, 'nothing more')

P.after(10, veh, ray)
T.check(#P.take() == 0, 'after without before: nothing')

T.done('test_groundprobe')
