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
- Implemented so far: tap/click source, `ImpactBridge`, and the `target_practice` test scene. Planned: replay and simulated-noise sources, Wi-Fi (UDP) hub source and later Bluetooth, 4-point calibration (a homography from wall to screen), pre-fractured shattering targets, a scoring and round framework.

## Phone limits
- About 100 moving physics bodies at most, simple collision shapes, and debris removed after a few seconds.
- Shatter using pieces made ahead of time (Blender Cell Fracture or VoronoiShatter), never fracture at runtime.
- Target a visible reaction within 100 ms of a hit; show an instant flash at the hit point while the ball flies.

## Future games
Target Practice → brick breaker or bottle stack → a tower-toppling game (cel-shaded, bodies locked to a flat plane, earn and level up ball types, ball types defined as data resources) → sports games (soccer penalties, pitching).

## Working rules
- Branch per feature and merge through pull requests; never commit to `main` directly.
- The full plan, costs and decisions live in the team's "Impact Wall Game Kit — Launch Plan & Cost Model" doc.
