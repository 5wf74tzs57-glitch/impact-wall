# Impact Wall: notes for Claude

## Product
- A $199 wall-target game kit, aimed at holiday 2027. An ESP32 hub with 4 piezo sensors and 4 microphones locates where a ball or foam dart hits a wall, using time differences between the sensors. A projector run from a phone shows the game on the wall.
- Tim does creative, UX and motion and is new to game development and git, so explain in plain language. John does hardware and firmware. Both build the games in Godot.
- Main buyers are teens and families with kids. The game is active: players walk up to collect the ball after each throw, so don't punish that walk with a running clock.

## Engine design (keep to this)
- Godot 4.7.2, GDScript with static types, **Mobile** renderer, **Jolt** 3D physics at 60 Hz, landscape.
- `addons/impact_core/` is the shared engine; each game lives in `games/<name>/` and uses it without changing it.
- Layers: hit sources → calibration → impact bridge → physics building blocks → game framework → games. Each layer only talks to the one below it.
- All hits become a `HitEvent` sent through the `HitBus` autoload. Games never read a hit source directly.
- **The projected wall is the camera's view.** `ImpactBridge` launches a virtual ball from the camera through the hit point. It flies straight (no gravity) until first contact, so it strikes exactly what was under the hit point.
- Implemented so far: tap/click source, `ImpactBridge`, `Breakable` (shatters into pieces prepared ahead of time: Voronoi shards from a Blender .glb via `pieces_scene`, or grid boxes as a fallback), the game framework (`RoundController`: rounds counted in throws, never a clock, best score in `user://scores.cfg`; `GameHud`), and Target Practice on an outdoor range with a forest instead of a back wall (10 throws; person-silhouette targets from `assets/targets/person_target.glb`; `RangeTarget` kinds POP_UP at near/mid/far rows (up 5 s), MOVER (far rail z=-20, tall post), DEPTH (walks toward/away between z -9 and -17 on a tall post) and PEEK (behind hay bales); any can be friendly (blue, smiley, -5); scoring bullseye 5 / rings 3, 2 / body 1, +1 moving, x2 beyond 8 m and x3 beyond 12.5 m, computed from the ball's straight path crossing the board face; misses = ball touches a static body or flies past z=-24; score clamps at 0). Targets never overlap on screen: each target's whole-life screen footprint is checked against live targets and the hay bales before it spawns. The board's RigidBody is top_level and placed from the rig every physics step (parenting a frozen body to a moving node drifts); tweens run in physics time. `Breakable` breaks frozen bodies on contact with any body in group `ImpactBridge.BALL_GROUP`, and `debris_parent` keeps shards alive after the target is freed. Keep near boards at least ~1/6 of the screen height so they're hittable on a projected wall. Headless tests must set `root.size = Vector2i(1280, 720)` (headless defaults to a square window, which changes screen layout). Wi-Fi hub source `UdpHitSource` (protocol v1 in `docs/hub_protocol.md`, a proposal awaiting John's review; `tools/hub_sim/fake_hub.py` is the reference sender; hub x,y are 0..1 with origin bottom-left, mapped through the replaceable `wall_to_screen` callable; it counts packets and records `last_problem` in plain words, and `hub_address` makes the game call a hub directly when broadcasts are blocked). `HubOverlay` (press H) shows it; `tools/hub_sim/listen.py` prints raw packets; checklist in `docs/hub_troubleshooting.md`. Planned: replay and simulated-noise sources, Bluetooth, 4-point calibration (a homography from wall to screen, which sets `wall_to_screen`).
- Tests (`tests/*.gd`, run with `godot --headless --path . -s res://tests/<name>.gd`) must not reference autoloads by name in classes they load; look them up with `get_node("/root/HitBus")`. Aim test throws with `camera.unproject_position()`, never fixed pixels (the headless screen size differs).

## iPhone builds
- Built on Tim's Mac (Xcode, free Personal Team, bundle ID `com.timmorris.impactwall`); steps and known fixes are in README "Building for iPhone". Godot's own xcodebuild step tends to fail; the reliable path is export → open `builds/ios/*.xcodeproj` in Xcode → pick the real iPhone → Run. Godot 4.7.2's iOS templates have no simulator slice.

## Phone limits
- About 100 moving physics bodies at most, simple collision shapes, and debris removed after a few seconds.
- Shatter using pieces made ahead of time (Blender Cell Fracture or VoronoiShatter), never fracture at runtime.
- Target a visible reaction within 100 ms of a hit; show an instant flash at the hit point while the ball flies.

## Future games
Target Practice → brick breaker or bottle stack → a tower-toppling game (cel-shaded, bodies locked to a flat plane, earn and level up ball types, ball types defined as data resources) → sports games (soccer penalties, pitching).

## Blender
- `tools/blender/impact_wall_tools.py` is a beginner-friendly add-on (Tim is a Blender beginner: keep tips plain) and holds `voronoi_fracture()`, which `tools/blender/make_target_shards.py` also uses.
- Pre-broken models are .glb files with an `Intact` mesh and a `Shards` empty whose children are the pieces. Every vertex's UV is its spot on the board's face, so one material (e.g. `games/target_practice/bullseye.gdshader`) spans the board and all shards; cut faces use the `Inside` material.
- In the cloud workspace, Blender runs as the PyPI package `bpy` (blender.org downloads are blocked); `import bpy` must come before `import bmesh`.

## Working rules
- Branch per feature and merge through pull requests; never commit to `main` directly.
- The full plan, costs and decisions live in the team's "Impact Wall Game Kit — Launch Plan & Cost Model" doc.
