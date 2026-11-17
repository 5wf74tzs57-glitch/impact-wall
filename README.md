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
| `games/target_practice/` | First test game |

## Settings worth knowing

- **Physics:** Jolt, at 60 ticks per second
- **Renderer:** Mobile
- **Orientation:** landscape (the game is projected)

## Working together

- Make a branch for each feature (for example `shatter-targets`). Don't work directly on `main`.
- Commit and push from GitHub Desktop, then open a pull request so the other person can look before it merges.
