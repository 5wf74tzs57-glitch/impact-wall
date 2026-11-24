# impact-wall

Games for the Impact Wall kit. An ESP32 hub with piezo sensors and microphones detects where a ball or foam dart hits a wall. A projector run from a phone shows the game on that wall.

## Getting started

1. Install **Godot 4.7.2** (standard version, not .NET) from https://godotengine.org/download. Use this exact version so the project opens the same for everyone.
2. Clone this repo with GitHub Desktop (**File → Clone repository**).
3. In Godot's Project Manager, click **Import**, pick this folder's `project.godot`, then **Import & Edit**.
4. Press **F5** (or the ▶ button) to run. Click to start, then throw 10 times at Tim's cartoon targets at four distances: pop-ups, movers sliding along a far rail, walkers coming toward or going away from you, and targets peeking out from behind hay bales. You score the number printed where you hit: chest rings 5 to 1, head bullseye 5 to 3 (rest of the head 2); +1 on a moving target, then x2 for mid-range and x3 for far targets. A head hit knocks off just the head, an outer-side hit breaks off that side, and a hit on the inner rings shatters the whole target. Hitting a blue smiley friendly costs 5. Click again on the results screen to play again.

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
| `addons/impact_core/sources/` | Where hits come from: `tap_hit_source.gd` (taps and clicks) and `udp_hit_source.gd` (the hub over Wi-Fi); Bluetooth later |
| `docs/hub_protocol.md` | The messages the hub and game send each other |
| `tools/hub_sim/fake_hub.py` | Pretends to be the hub, for testing without hardware |
| `addons/impact_core/impact_bridge.gd` | Turns hits into virtual balls flying into the scene, plus a hit flash |
| `addons/impact_core/breakable.gd` | Add to any physics object to make it shatter into pieces on a hard hit |
| `assets/targets/` | Models made in Blender (the target and its shards) |
| `tools/blender/` | Blender helper panel and the script that makes the shards |
| `addons/impact_core/framework/` | Game framework: `RoundController` (rounds of throws, scores, best score saved on the device) and `GameHud` (start/results screens, status line, score pops) |
| `games/target_practice/` | Target Practice on an outdoor range: `range_target.gd` (pop-up, mover, walker, peek-from-cover; friendly or not), `target_practice.gd` (the range, the forest, spawning without overlaps, scoring), `person_target.gdshader` / `friendly.gdshader` (target faces) |

## Settings worth knowing

- **Physics:** Jolt, at 60 ticks per second
- **Renderer:** Mobile
- **Orientation:** landscape (the game is projected)

## Building for iPhone

iPhone builds need a Mac with **Xcode** (free, from the App Store; install the iOS platform when it asks) and an Apple ID. A free Apple ID works for testing on your own phone.

### One-time setup
1. **Xcode → Settings → Apple Accounts**: sign in with your Apple ID, click your name, then **Manage Certificates → + → Apple Development**.
2. **Your Team ID**: open **Keychain Access → login → My Certificates**, double-click **Apple Development: …**, and copy the **Organizational Unit** (a 10-character code). Not the code in brackets in the certificate's name.
3. **Xcode → Settings → Locations → Command Line Tools**: choose **Xcode**. If this is left on "Command Line Tools", Godot's export fails with *"xcodebuild requires Xcode"*.
4. **iPhone**: plug it in, unlock it, tap **Trust**, then **Settings → Privacy & Security → Developer Mode → On** (it restarts).
5. **Godot**: **Editor → Manage Export Templates → Download and Install** (the iOS templates are enough).

### Each build
1. Pull the latest in GitHub Desktop, then in Godot **Project → Reload Current Project**.
2. **Project → Export… → iOS** (the preset is saved in `export_presets.cfg`; set **App Store Team ID** to your own Team ID). Click **Export Project…** and save into `builds/ios` (git ignores this folder).
   - If Godot then shows *"Xcode Build: Failed to run xcodebuild"*, carry on anyway: the Xcode project was still created.
3. Open `builds/ios/Impact Wall.xcodeproj` in Xcode.
4. At the top, pick **your iPhone**, not a Simulator. (A Simulator gives *"Undefined symbol: _main"*, because Godot only includes the engine for real iPhones.)
5. **Signing & Capabilities**: tick **Automatically manage signing**, Team = your **(Personal Team)**.
6. Press **▶ Run** (⌘R). **Build** (⌘B) only builds; it doesn't install.
7. First time only: if it says the developer isn't trusted, on the iPhone go to **Settings → General → VPN & Device Management**, tap your Apple ID and **Trust**, then open **Impact Wall**.

With a free Apple ID the app stops opening after **7 days**. Run it from Xcode again to reinstall. A paid developer account ($99/year) removes that limit and allows TestFlight builds for other people.

## Connecting the hub

The game listens for John's hub over Wi-Fi (UDP port 4210). The message format is in [`docs/hub_protocol.md`](docs/hub_protocol.md). Taps and clicks always work too.

No hub yet? `tools/hub_sim/fake_hub.py` pretends to be one (plain Python 3, nothing to install). With the game running (F5), open a terminal in the repo folder and run:

```
python tools/hub_sim/fake_hub.py --target 127.0.0.1 --random 5
```

The start screen changes to "Hub connected (fake-hub)". The first hit starts the round, and the next ones are throws. To send hits to a phone, use the phone's Wi-Fi address instead of `127.0.0.1`. To type hits yourself, use `--click`.

Real hub not connecting? Press **H** in the game for hub info, and follow [`docs/hub_troubleshooting.md`](docs/hub_troubleshooting.md). `tools/hub_sim/listen.py` prints everything that arrives on the hub port.

## Blender

### Helper panel (for anyone, beginners welcome)
`tools/blender/impact_wall_tools.py` adds an **Impact Wall** tab to Blender with one-click fixes for origins and transforms, each with a plain-language tip, plus a **Shatter Selected** button.

To install it (once per computer):
1. In Blender: **Edit → Preferences → Add-ons**.
2. Click the small **⌄** arrow at the top right → **Install from Disk…**
3. Choose `tools/blender/impact_wall_tools.py` from this repo, and make sure **Impact Wall Tools** is ticked.
4. In the 3D view, press **N** to open the sidebar and click the **Impact Wall** tab.

### Tim's cartoon target
The game's target is designed in `assets/source/targets.blend` (Godot ignores that folder) as four convex parts, Head, Left, Center and Right, exported to `assets/targets/cartoon_target.glb`. After changing it, rebuild the game's copy with its pre-broken shards (and the artwork reduced to 1024) with:

```
blender --background --python tools/blender/make_cartoon_shards.py -- assets/targets/cartoon_target.glb assets/targets/cartoon_target_shards.glb
```

If the rings or head move in the artwork, update the matching numbers at the top of `games/target_practice/range_target.gd`, then run `tests/target_alignment_test.gd`. It checks the hit area against the drawn shape and that every ring scores its printed number.

### Rebuilding the old square target's shards
`assets/targets/person_target.glb` (the person silhouette plus 24 pre-broken shards, made by `tools/blender/make_person_target.py`) and the older square `assets/targets/target_shards.glb` are made by scripts, so it can be rebuilt any time, for example with more pieces:

```
blender --background --python tools/blender/make_target_shards.py -- assets/targets/target_shards.glb
```

Change `PIECES`, `SEED` (a different break pattern) or `CENTER_BIAS` (more small pieces in the middle) at the top of the script.

## Checking the project

Two automatic tests, run from the project folder with no window needed:

- `tests/smoke_test.gd`: start a round, hit a near bullseye (+5), a friendly (-5), a far bullseye (5 x3 = +15), then miss (+0).
- `tests/target_alignment_test.gd`: the hit area matches the drawn target, and throws at every ring score the printed number and break the right part.
- `tests/spawn_test.gd`: let targets appear on their own (sped up) and check none ever overlap on screen or hide behind a bale; then hit a walker.
- `tests/round_test.gd`: play a full 10-throw round and check the results screen and saved best score.
- `tests/udp_test.gd`: pretend to be the hub and check the game connects, answers, and turns hits into throws.


```
godot --headless --path . -s res://tests/smoke_test.gd
```

Swap in `round_test.gd` for the second one. Each prints `PASS` or `FAIL`. Run them before opening a pull request.

## Working together

- Make a branch for each feature (for example `shatter-targets`). Don't work directly on `main`.
- Commit and push from GitHub Desktop, then open a pull request so the other person can look before it merges.
