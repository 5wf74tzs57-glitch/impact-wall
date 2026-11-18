"""Pretend to be the Impact Wall hub, so the game can be tested without hardware.

Plain Python 3, nothing to install. Run it on any computer on the same Wi-Fi
as the game (or the same computer). It speaks the format in docs/hub_protocol.md.

Examples:
  python tools/hub_sim/fake_hub.py --target 127.0.0.1 --random 5
      game on this computer: say hello, then 5 random hits, one every 2 s
  python tools/hub_sim/fake_hub.py --target 192.168.1.23 --click
      game on a phone at that address: type "x y" (0 to 1) to send a hit
  python tools/hub_sim/fake_hub.py --random 10 --noise 0.02
      no --target: find the game by broadcasting; add a little aiming error
  python tools/hub_sim/fake_hub.py --target 127.0.0.1 --replay hits.csv
      send hits from a CSV file with columns x,y[,force]

The first hit on the game's start screen starts the round; the rest are throws.
"""

import argparse
import csv
import json
import random
import socket
import time

PORT = 4210
VERSION = 1


class FakeHub:
    def __init__(self, target, name, noise):
        self.target = target or "255.255.255.255"
        self.name = name
        self.noise = noise
        self.next_id = 1
        self.start = time.monotonic()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.bind(("", 0))
        self.sock.settimeout(0.2)

    def send(self, message, address=None):
        message = dict(message, v=VERSION)
        self.sock.sendto(json.dumps(message).encode(), (address or self.target, PORT))

    def replies(self, wait):
        """Messages the game sent back within `wait` seconds."""
        end = time.monotonic() + wait
        got = []
        while time.monotonic() < end:
            try:
                data, addr = self.sock.recvfrom(2048)
            except socket.timeout:
                continue
            try:
                got.append((json.loads(data.decode()), addr))
            except ValueError:
                pass
        return got

    def connect(self, tries=5):
        for _ in range(tries):
            self.send({"type": "hello", "hub": self.name, "fw": "sim"})
            for message, addr in self.replies(2.0):
                if message.get("type") == "connect":
                    self.target = addr[0]  # Talk to the game directly from now on.
                    print(f"Connected to the game at {addr[0]}")
                    return True
        print("No answer from the game. Is it running, on the same Wi-Fi, and is the address right?")
        return False

    def hit(self, x, y, force=0.7):
        if self.noise:
            x += random.gauss(0, self.noise)
            y += random.gauss(0, self.noise)
        x, y = min(max(x, 0.0), 1.0), min(max(y, 0.0), 1.0)
        hit_id = self.next_id
        self.next_id += 1
        message = {"type": "hit", "id": hit_id, "t_ms": int((time.monotonic() - self.start) * 1000),
                   "x": round(x, 4), "y": round(y, 4), "force": round(force, 3)}
        for attempt in range(3):  # Resend if the game doesn't acknowledge it.
            self.send(message)
            if any(m.get("type") == "ack" and m.get("id") == hit_id for m, _ in self.replies(0.3)):
                print(f"hit {hit_id}: x={x:.2f} y={y:.2f} force={force:.2f}  (acknowledged)")
                return True
        print(f"hit {hit_id}: x={x:.2f} y={y:.2f}  (no acknowledgement)")
        return False


def main():
    parser = argparse.ArgumentParser(description="Pretend to be the Impact Wall hub.")
    parser.add_argument("--target", help="game's IP address (default: broadcast to find it)")
    parser.add_argument("--name", default="fake-hub", help="hub name shown in the game")
    parser.add_argument("--noise", type=float, default=0.0,
                        help="random aiming error, as a share of the wall (e.g. 0.02)")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--random", type=int, metavar="N", help="send N random hits")
    mode.add_argument("--click", action="store_true", help="type hits by hand")
    mode.add_argument("--replay", metavar="CSV", help="send hits from a CSV file (x,y[,force])")
    parser.add_argument("--every", type=float, default=2.0, help="seconds between hits (default 2)")
    args = parser.parse_args()

    hub = FakeHub(args.target, args.name, args.noise)
    if not hub.connect():
        return
    if args.random:
        for _ in range(args.random):
            hub.hit(random.uniform(0.15, 0.85), random.uniform(0.25, 0.75), random.uniform(0.4, 1.0))
            time.sleep(args.every)
    elif args.replay:
        with open(args.replay, newline="") as f:
            for row in csv.DictReader(f):
                hub.hit(float(row["x"]), float(row["y"]), float(row.get("force") or 0.7))
                time.sleep(args.every)
    else:
        print('Type a hit as "x y" or "x y force" (each 0 to 1; 0 0 = bottom-left). Empty line quits.')
        while True:
            line = input("> ").strip()
            if not line:
                break
            parts = [float(p) for p in line.split()]
            hub.hit(*parts[:3])


if __name__ == "__main__":
    main()
