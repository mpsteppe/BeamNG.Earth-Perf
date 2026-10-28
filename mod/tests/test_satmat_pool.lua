-- luajit mod/tests/test_satmat_pool.lua  (a restarted server takes over our far-tile Material pool: satmat.pool,
-- satmat.takeFreed, 2026-10-28)
-- hello.farPool names the pool we hold the most of, how many names it has and which are shown; the shown ones are
-- reported (once) when no tile shows them any more.
local dir = (arg[0]:match('^(.*)[/\\]') or '.')
local T = dofile(dir .. '/testlib.lua')
dofile(dir .. '/stubs.lua')
local satmat = require('beamngEarth/satmat')

FS = { fileExists = function() return true end }

T.check(satmat.pool() == nil, 'no pooled Materials: no pool')
local tag, n = satmat.poolOf('bngEarthFar_0918_00042')
T.check(tag == '0918' and n == 42, 'a pooled name: its tag and number')
T.check(satmat.poolOf('bngEarthFar_v3') == nil, 'the static far material is no pooled one')

for i = 0, 4 do satmat.create(string.format('bngEarthFar_aaaa_%05d', i), '/t/a' .. i .. '.dds') end
for i = 0, 1 do satmat.create(string.format('bngEarthFar_bbbb_%05d', i), '/t/b' .. i .. '.dds') end
satmat.ref('bngEarthFar_aaaa_00001', '/t/a1.dds')
satmat.ref('bngEarthFar_aaaa_00004', '/t/a4.dds')
satmat.ref('bngEarthFar_bbbb_00000', '/t/b0.dds')

local p = satmat.pool()
T.check(p and p.tag == 'aaaa', 'the pool we hold the most of')
T.check(p.made == 5, 'its size: the highest number + 1')
T.check(#p.inUse == 2 and p.inUse[1] == 1 and p.inUse[2] == 4, 'its shown names')
T.check(satmat.takeFreed() == nil, 'nothing freed yet')

satmat.unref('bngEarthFar_bbbb_00000')
T.check(satmat.takeFreed() == nil, 'another pool\'s name is not reported')
satmat.unref('bngEarthFar_aaaa_00004')
local f = satmat.takeFreed()
T.check(f and f.tag == 'aaaa' and #f.n == 1 and f.n[1] == 4, 'a shown name no longer shown is reported')
T.check(satmat.takeFreed() == nil, 'reported once')
satmat.ref('bngEarthFar_aaaa_00004', '/t/a4.dds')
satmat.unref('bngEarthFar_aaaa_00004')
T.check(satmat.takeFreed() == nil, 'a name the new server gave out again is its own to track')

T.done('test_satmat_pool')
