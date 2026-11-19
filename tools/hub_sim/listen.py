"""Show every message arriving on a UDP port, to see what the hub really sends.

Plain Python 3, nothing to install. Close the game first (only one program
can listen on a port at a time), power on the hub, then run:

  python tools/hub_sim/listen.py
      listen on port 4210 (the game's port) and print everything that arrives
  python tools/hub_sim/listen.py --port 5000
      listen on another port, if the hub sends somewhere else
  python tools/hub_sim/listen.py --send-connect
      also answer "hello" with "connect" and hits with "ack", like the game

Nothing printed at all = nothing is reaching this computer: see
docs/hub_troubleshooting.md (same Wi-Fi? firewall? right port?).
"""

import argparse
import json
import socket
import time


def local_addresses():
    """Best guess at this computer's address on the local network."""
    addresses = set()
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("10.255.255.255", 1))  # Sends nothing; just picks the network card.
        addresses.add(probe.getsockname()[0])
        probe.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(info[4][0])
    except OSError:
        pass
    return sorted(a for a in addresses if not a.startswith("127.")) or ["(unknown)"]


def main():
    parser = argparse.ArgumentParser(description="Print every UDP message arriving on a port.")
    parser.add_argument("--port", type=int, default=4210)
    parser.add_argument("--send-connect", action="store_true",
                        help='answer "hello" with "connect" and hits with "ack", like the game does')
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("", args.port))
    except OSError as err:
        print(f"Can't listen on port {args.port}: {err}. Is the game still running? Close it and try again.")
        return
    print(f"Listening on UDP port {args.port}. This computer: {', '.join(local_addresses())}")
    print("Waiting for messages (Ctrl+C to stop)...")
    count = 0
    while True:
        data, (ip, port) = sock.recvfrom(4096)
        count += 1
        text = data.decode("utf-8", errors="replace")
        stamp = time.strftime("%H:%M:%S")
        try:
            message = json.loads(text)
            kind = message.get("type", "?") if isinstance(message, dict) else "not an object"
            note = f"JSON, type={kind}"
            if isinstance(message, dict) and "v" not in message:
                note += ', no "v" field'
        except ValueError:
            message = None
            note = "NOT JSON"
        print(f"[{stamp}] #{count} from {ip}:{port}  ({note})\n    {text[:300]}")
        if args.send_connect and isinstance(message, dict):
            reply = None
            if message.get("type") == "hello":
                reply = {"v": 1, "type": "connect"}
            elif message.get("type") == "hit":
                reply = {"v": 1, "type": "ack", "id": message.get("id")}
            if reply:
                sock.sendto(json.dumps(reply).encode(), (ip, port))
                print(f"    -> replied {reply['type']}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
