# Performance changes on top of 1.7.0-beta

This branch is BeamNG.Earth **1.7.0-beta** plus performance and stutter fixes, each measured in game with A/B drives.
It installs and runs exactly like the release (see [README.md](README.md)): nothing here needs a setting, and every
change is in the mod's Lua or the server's Python, apart from one small change to the Rust GPU picker.

Everything was measured on one PC (i7-12700K, RTX 5080, Windows 11, BeamNG.drive 0.40) driving in Finland at
60-230 mph. FPS is the median over seconds above 60 mph; "spikes" are frames over 50 ms. Speeds differed between
drives, so compare the causes more than the totals.

To review commit by commit: `git log --oneline v1.7.0-beta..HEAD` (about 15 commits, 30 files).

## The big one: Lua garbage collection pacing (`core.lua`, `core.gcStep`)

**Result: 78 → 105-109 fps moving, 82 → 124-142 fps standing; spikes over 50 ms 7.6 → 2.1 a minute.**

Per-second engine timing showed the frame was bound by the main thread, and the mod's Lua took a constant ~3.7 ms
of a 12.8 ms frame, standing or moving. Most of it was garbage collection: on a ~185 MB heap a new GC cycle began
every frame (the mod's own step, 1.7 ms), plus the engine's LuaGC (0.7 ms).

- After a cycle ends, the mod takes no GC steps until the heap has grown `GC_GROW` (25 %).
- LuaJIT's own collector is told to wait (`collectgarbage('setpause', GC_PAUSE)`, 400; its default is 200), set again
  at each cycle's end. Without it, LuaJIT ran its own cycles while resting, and their last pass took one 100-156 ms
  frame.
- The settings are module fields (`M.GC_STEP_MS`, `M.GC_STEP_KB`, ...), not locals: 1.7.0's `core.lua` sits at Lua's
  200-local limit, and one more local stops the whole mod loading. **Watch for this on every merge.**

| | before | GC pacing | + setpause |
|---|---|---|---|
| FPS at 60+ mph | 78 | 109 | 105 |
| FPS standing | 82 | 142 | 124 |
| spikes over 50 ms | 7.6 / min | 7.3 / min | 2.1 / min |
| worst engine-GC spike | 128 ms | 156 ms | 82 ms |

## Stutter fixes

Each hitch frame (50 ms+) is now logged with its cause: the mod's units over 2 ms, the trees made in it, the heap.
That found these, in order:

1. **Collision rebuilds at speed** (`roads.lua`): a rebuild costs ~0.15-0.31 ms per 1,000 colliding triangles, and
   the colliders' reach was 2 km / 14 s ahead. Now 1.2 km / 9 s (`COLLIDE_M`, `COLLIDE_LEAD_S`). At ~190 mph the
   rebuild hitches (were every ~3 s) went.
2. **A tree shape's first item in the level** costs the engine 5-50 ms. Standing frames made up to 26 of them at once
   (115-143 ms). Now at most one new shape a frame (`trees.FIRSTS_PER_FRAME`), and only for shapes never loaded in
   the level, so after a rebase the forest is not held back.
3. **Railway meshes** (up to 2.2 MB a tile, every sleeper a box, all colliding): 63-72 ms frames. Now a lean
   collision mesh of the ballast bed and decks (`railcol`, server `rail_collision`); the drawn rails and sleepers
   only render, like the buildings' `bldcol` and sidewalks' `walkcol`.

## Smaller fixes

- **Far-tile Materials leaked per server restart** (`satmat.lua`, `matslots.py`): each server run made its own pool
  and the game kept them all (3,174 Materials for 829 tiles after 3 restarts). The mod now sends its pool in `hello`
  (`farPool`) and a fresh server adopts it; names still shown stay reserved until the mod reports them freed
  (`pose.farPoolFreed`).
- **Ground blocks in the revisit cache** (`blockworker.py`, kind `"ground"`): a place visited again loads its terrain
  block from disk (2.66 s build → 0.19 s). Kept only when complete.
- **Windows 11 hybrid CPUs** (`budget.py`): the below-normal server was put on the E-cores (4 E-cores at 100 %,
  P-cores idle, the ground ahead late). The server opts out of power throttling; its priority class stays.
- **GPU by name** (`BNGE_GPU_NAME`, `gpu.rs`, `fast.py`): the server's GPU kernels on a second card the game does not
  draw with. If no card matches, the server keeps its CPU path rather than share the game's GPU. Opt-in only; the
  `earthfast` binaries in this branch are still 1.7.0's, so it needs `cargo build --release` in `native/earthfast`
  to take effect (without the variable nothing changes).

## Options for testing (all off by default)

| variable | effect |
|---|---|
| `BNGE_LIGHT=1` | a lighter world: coarser far tiles (`--lod-k 2.0`), the mod's trees thinned past 300 m |
| `BNGE_FRAME_BUDGET=0.25-1` | the mod's per-frame budgets (far streaming, trees, GC) scaled |
| `BNGE_SERVER_CPUS` / `BNGE_GAME_CPUS` | exact CPU sets, e.g. `8-15` and `0-7` |
| `BNE_GC_STEP_MS` | the GC step's time a frame, 1 ms by default, 0 = off (read by the game, so set it before starting BeamNG) |

## Diagnostics added

- `groundprobe.lua`: round every rebase and terrain-follow commit, the ground ahead of the car, its height above the
  ground, the colliders made near it and, for 10 s after a rebase, the road and tree tiles round it (ghost or new,
  meshes made) and every ghost released, in the server log tagged `probe`.
- `tools/perf_watch.py`: per-second samples with engine stage timing and a report's "frame time by stage" table;
  works on Windows (psutil).

## Ruled out (measured, no FPS change)

Server CPU contention and E-cores, tree density and far detail (`BNGE_LIGHT`), halving the per-frame budgets, the
server's GPU work on the game's card. New ground costs only ~0.6 ms a frame over driving on built ground.

## Still open

- Render 23-40 ms frames with the mod's `world` / `net` at ~9-10 ms, frequent at 190+ mph; the rebase frame itself.
- Road bridge decks (80-270 KB) still make 58-68 ms frames now and then.
- Rarely after a fast rebase every tree stops being drawn for some seconds, while all of them still exist and collide
  (seen twice; the probe above is there to catch it).
- One frame right after a rebase where a ray finds no ground under the car.

## Tests

Mod Lua tests (`mod/tests/*.lua`, LuaJIT) and the server's `unittest` suite cover the changes (`test_groundprobe`,
`test_satmat_pool`, `test_trees`, `test_roads`, `test_matslots`, `test_blockworker`, `test_protocol_agreement`, ...).
`test_roads`' "then the pending rebuild runs" and "dropped tile: mesh deleted, collision reloaded" are timing tests
that fail now and then, with or without these changes.

Run the server's tests as `python -m unittest discover -s tests -t tests` in `server/` (they import each other).
On Windows these fail on unchanged 1.7.0-beta too, so not because of this branch: `test_apppaths`, `test_bmplaunch`,
`test_launcher_linux`, `test_netfetch` (its fake connection lacks `context`), `test_otto_bridge`.
