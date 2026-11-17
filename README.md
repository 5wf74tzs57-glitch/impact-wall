# impact-wall

Games for the Impact Wall kit. An ESP32 hub with piezo sensors and microphones detects where a ball or foam dart hits a wall. A projector run from a phone shows the game on that wall.

## Getting started

1. Install **Godot 4.7.2** (standard version, not .NET) from https://godotengine.org/download. Use this exact version so the project opens the same for everyone.
2. Clone this repo with GitHub Desktop (**File → Clone repository**).
3. In Godot's Project Manager, click **Import**, pick this folder's `project.godot`, then **Import & Edit**.
4. Press **F5** (or the ▶ button) to run. Click anywhere to throw a ball. Shatter the target to score.

On a phone, a tap does the same as a click.

## How it fits together

Every hit, whatever produced it, becomes a `HitEvent` (screen position, force, time). It's sent through the global `HitBus`, and games only listen to `HitBus`. A game doesn't know or care whether a hit came from a tap or the real hub.

`ImpactBridge` turns each hit into a virtual ball launched from the camera, through the hit point, into the 3D scene. The projected wall is the camera's view, so the ball strikes whatever was under the spot that was hit.

## Folders

| Path | What's in it |
| --- | --- |
| `addons/impact_core/` | The shared engine that every game uses |
| `addons/impact_core/hit_event.gd` | One hit: position, force, time, source |
| `addons/impact_core/hit_bus.gd` | Global hit channel (autoload `HitBus`) |
| `addons/impact_core/sources/` | Where hits come from. `tap_hit_source.gd` turns taps and clicks into hits; Wi-Fi and Bluetooth hub sources come later |
| `addons/impact_core/impact_bridge.gd` | Turns hits into virtual balls flying into the scene, plus a hit flash |
| `addons/impact_core/breakable.gd` | Add to any physics object to make it shatter into pieces on a hard hit |
| `assets/targets/` | Models made in Blender (the target and its shards) |
| `tools/blender/` | Blender helper panel and the script that makes the shards |
| `games/target_practice/` | First test game |

## Settings worth knowing

- **Physics:** Jolt, at 60 ticks per second
- **Renderer:** Mobile
- **Orientation:** landscape (the game is projected)

## Blender

### Helper panel (for anyone, beginners welcome)
`tools/blender/impact_wall_tools.py` adds an **Impact Wall** tab to Blender with one-click fixes for origins and transforms, each with a plain-language tip, plus a **Shatter Selected** button.

To install it (once per computer):
1. In Blender: **Edit → Preferences → Add-ons**.
2. Click the small **⌄** arrow at the top right → **Install from Disk…**
3. Choose `tools/blender/impact_wall_tools.py` from this repo, and make sure **Impact Wall Tools** is ticked.
4. In the 3D view, press **N** to open the sidebar and click the **Impact Wall** tab.

### Rebuilding the target's shards
`assets/targets/target_shards.glb` (the board plus 24 pre-broken shards) is made by a script, so it can be rebuilt any time, for example with more pieces:

```
blender --background --python tools/blender/make_target_shards.py -- assets/targets/target_shards.glb
```

Change `PIECES`, `SEED` (a different break pattern) or `CENTER_BIAS` (more small pieces in the middle) at the top of the script.

## Checking the project

`tests/smoke_test.gd` checks that a hit on the target shatters it and scores. Run it from the project folder, no window needed:

```
godot --headless --path . -s res://tests/smoke_test.gd
```

It prints `PASS` or `FAIL`. Run it before opening a pull request.

## Working together

- Make a branch for each feature (for example `shatter-targets`). Don't work directly on `main`.
- Commit and push from GitHub Desktop, then open a pull request so the other person can look before it merges.
