# Hub won't connect? A 5-minute checklist

The game shows **"No hub found"** until it receives a `hello` (or `hit`) in the format in [`hub_protocol.md`](hub_protocol.md). Work down this list. Each step tells you which side the problem is on.

## 1. Is anything arriving at all?

Close the game, power on the hub, and on the same computer run:

```
python tools/hub_sim/listen.py
```

It prints every message that reaches UDP port 4210, with the sender's address.

- **Messages appear** → the network is fine; go to step 3.
- **Nothing appears** → nothing from the hub is reaching this computer; go to step 2.

(In the game you can see the same thing: press **H** for hub info, which shows "Packets in" and the last packet.)

## 2. Nothing arrives: network and firewall

- **Same network?** The hub and the computer/phone must be on the same Wi-Fi. Guest networks usually block devices from seeing each other.
- **Firewall:** the first time the game (or Python) runs, Windows asks whether to allow it on the network. If that was dismissed, go to Windows Security → Firewall & network protection → Allow an app through firewall, and tick **Godot** (and **Python**) for **Private** networks. On a Mac: System Settings → Network → Firewall → Options.
- **Port and address:** the hub should send to port **4210**, either to the broadcast address `255.255.255.255` or to the computer's own address (shown by `listen.py` and the H overlay).
- **Router blocks broadcasts?** Some routers do. Then the game can call the hub instead: set `hub_address` on the `UdpHitSource` to the hub's IP (for example in `target_practice.gd`: `_hub.hub_address = "192.168.1.50"`), and the game sends `connect` to it every 2 seconds. The hub then needs to listen on port 4210 too.
- Still nothing? Try a different port on both sides with `listen.py --port 5000`, in case something else is using 4210.

## 3. Messages arrive but the game doesn't connect: format

Compare what `listen.py` printed with the examples in `hub_protocol.md`. The H overlay in the game shows the **Problem** line, for example:

| Problem shown | Fix on the hub |
| --- | --- |
| Last packet wasn't JSON | Send the JSON text, one object per packet, no extra bytes |
| Message is protocol version 2 | Send `"v": 1` |
| Unknown message type "..." | Use `"type": "hello"`, `"hit"` or `"raw"` |
| Message had no "v" field | Works, but add `"v": 1` |

A minimal hello the game accepts:
```json
{"v": 1, "type": "hello", "hub": "impact-hub-01"}
```

## 4. Connected but hits land in the wrong place

Expected until calibration exists (Benchmark 8): `x` and `y` must be 0 to 1, with `0,0` at the bottom-left sensor. Check by sending a few hits with `listen.py` running.

## What to send back if it's still stuck

A photo of the game's H overlay, or the first few lines `listen.py` printed with the hub on.
