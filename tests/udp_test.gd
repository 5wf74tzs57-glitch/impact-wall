extends SceneTree
## UDP test: pretend to be the hub on this computer and check the game
## connects, answers, turns hits into throws and ignores repeated hits.
##
##   godot --headless --path . -s res://tests/udp_test.gd

const SCENE := "res://games/target_practice/target_practice.tscn"

var hub := PacketPeerUDP.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(game)
	await _frames(10)
	var source: UdpHitSource = game.get("_hub")
	hub.bind(0, "127.0.0.1")
	hub.set_dest_address("127.0.0.1", source.port)

	_send({"type": "hello", "hub": "test-hub", "fw": "test"})
	await _frames(10)
	var got_connect := "connect" in _replies()

	_send({"type": "hit", "id": 1, "x": 0.5, "y": 0.5, "force": 0.7})  # starts the round
	await _frames(10)
	_send({"type": "hit", "id": 2, "x": 0.3, "y": 0.6, "force": 0.8})  # a throw
	_send({"type": "hit", "id": 2, "x": 0.3, "y": 0.6, "force": 0.8})  # repeat: ignored
	await _frames(10)
	var replies := _replies()
	var round: RoundController = game.get("_round")
	var launched: int = game.get("_balls_launched")

	var ok := source.connected and source.hub_name == "test-hub" and got_connect \
		and replies.count("ack") >= 2 and round.state == RoundController.State.PLAYING and launched == 1
	print(("PASS: " if ok else "FAIL: ") + "connected=%s name=%s connect_reply=%s acks=%d playing=%s balls=%d"
		% [source.connected, source.hub_name, got_connect, replies.count("ack"),
		round.state == RoundController.State.PLAYING, launched])
	quit(0 if ok else 1)


func _send(message: Dictionary) -> void:
	message["v"] = 1
	hub.put_packet(JSON.stringify(message).to_utf8_buffer())


## The "type" of every message the game sent back since last time.
func _replies() -> Array[String]:
	var types: Array[String] = []
	while hub.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(hub.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			types.append(str(msg.get("type", "")))
	return types


func _frames(n: int) -> void:
	for i in n:
		await process_frame
