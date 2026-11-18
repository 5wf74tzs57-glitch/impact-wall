# Hub ↔ game messages (protocol v1): **proposal for John to review**

How the ESP32 hub tells the game about hits over Wi-Fi. The game side is built and tested against this (`addons/impact_core/sources/udp_hit_source.gd`). `tools/hub_sim/fake_hub.py` is a working reference sender in Python. Anything here can change: tell Tim/Claude and both sides get updated.

## Transport

- **UDP** on the local Wi-Fi network, **port 4210**, both directions.
- Each packet is **one JSON object** (UTF-8, no newline needed). Every message carries `"v": 1`.
- The phone and hub must be on the same network (home Wi-Fi, or the hub's own access point; see open questions).

## Finding each other

1. The hub broadcasts **hello** to `255.255.255.255:4210` every 2 s until it gets a reply:
   ```json
   {"v": 1, "type": "hello", "hub": "impact-hub-01", "fw": "0.1.0"}
   ```
2. The game answers **connect**, sent to the address and port the hello came from:
   ```json
   {"v": 1, "type": "connect"}
   ```
3. From then on, the hub sends to the game's address directly (the reply's source IP).

## Hits

The hub sends one **hit** per impact:
```json
{"v": 1, "type": "hit", "id": 42, "t_ms": 123456, "x": 0.43, "y": 0.61, "force": 0.7}
```

| Field | Meaning |
| --- | --- |
| `id` | Counts up by 1 per hit. Lets the game ignore repeats. |
| `t_ms` | The hub's clock when the hit happened, in milliseconds (for latency checks later). |
| `x`, `y` | Where on the wall, **0 to 1** across the area inside the sensors. `0,0` = bottom-left sensor, `1,1` = top-right. |
| `force` | How hard, **0 to 1** (from piezo amplitude). Optional; the game uses 0.7 if missing. |

The game answers each hit with **ack**:
```json
{"v": 1, "type": "ack", "id": 42}
```
If no ack arrives within about 300 ms, resend the same hit (same `id`) up to 2 more times. The game ignores repeats.

## Raw sensor data (optional, for tuning)

To tune the location math, the hub can also send what it measured:
```json
{"v": 1, "type": "raw", "id": 42, "dt_us": [0, 312, 544, 701], "amp": [880, 610, 455, 390]}
```
`dt_us` = arrival time at each sensor relative to the first, in microseconds; `amp` = peak level per sensor. The game appends these to `hit_log.csv` in its user folder and doesn't use them for gameplay.

## Until calibration

The game maps `x,y` straight onto the whole screen for now. Benchmark 8 adds a 4-point calibration (throw at four projected markers), which replaces that mapping. The hub keeps sending wall coordinates either way.

## Open questions for John

1. Is port 4210 free on your side, and is JSON easy (ArduinoJson), or would you rather send a fixed binary layout?
2. Will the hub solve `x,y` itself in the first version, or send only `raw` timings and let the phone solve them?
3. Which corner is sensor 1, and is "0 to 1 inside the sensors" a good coordinate system?
4. Home Wi-Fi only, or should the hub also offer its own Wi-Fi network (an access point) for places without Wi-Fi?
