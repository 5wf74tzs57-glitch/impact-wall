class_name UdpHitSource
extends Node
## Receives hits from the Impact Wall hub over Wi-Fi and turns them into hits
## for the game, exactly like a tap would be.
##
## Message format: docs/hub_protocol.md (UDP, one JSON object per packet).
## The hub broadcasts "hello" until we answer "connect"; then it sends "hit"
## messages with a wall position from 0 to 1, and we answer each with "ack".

signal hub_connected(hub_name: String)

const PROTOCOL_VERSION := 1

## UDP port the game listens on (the hub sends here).
@export var port: int = 4210
## Where "raw" sensor timings are saved, for tuning the location math.
@export var raw_log_path: String = "user://hit_log.csv"
## Force used when a hit message doesn't include one.
@export_range(0.0, 1.0) var default_force: float = 0.7
## Optional: the hub's IP address (e.g. "192.168.1.50"). When set, the game
## keeps saying "connect" to it, for routers that block the hub's broadcast.
@export var hub_address: String = ""

## Optional: a function (wall_pos: Vector2) -> Vector2 that turns a wall
## position (0..1, origin bottom-left) into a screen position. Calibration
## will set this; until then the wall maps straight onto the whole screen.
var wall_to_screen: Callable

var connected := false
var hub_name := ""
var last_message_ms := 0

# What has arrived, for the hub info overlay (press H) and troubleshooting.
var listening := false
var packets_received := 0
var last_packet_from := ""
var last_packet_text := ""
## Why the last message wasn't understood, in plain words ("" = no problem).
var last_problem := ""

var _udp := PacketPeerUDP.new()
var _hub_ip := ""
var _hub_port := 0
var _recent_ids: Array[int] = []
var _hit_bus: Node
var _probe_timer := 0.0


func _ready() -> void:
	# Looked up at run time so tests can load this class (see CLAUDE.md).
	_hit_bus = get_node("/root/HitBus")
	_udp.set_broadcast_enabled(true)
	var err := _udp.bind(port, "*")
	listening = err == OK
	if err != OK:
		last_problem = "Can't listen on port %d (another copy of the game running?)" % port
		push_warning("UdpHitSource: can't listen on port %d (error %d). Is another copy of the game running?" % [port, err])


func _exit_tree() -> void:
	_udp.close()


func _process(delta: float) -> void:
	_probe_hub_address(delta)
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var from_ip := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		var text := packet.get_string_from_utf8()
		packets_received += 1
		last_packet_from = "%s:%d" % [from_ip, from_port]
		last_packet_text = text.left(200)
		var message: Variant = JSON.parse_string(text)
		if message is Dictionary:
			_handle(message, from_ip, from_port)
		else:
			last_problem = "Last packet wasn't JSON (see docs/hub_protocol.md for the format)"


func _probe_hub_address(delta: float) -> void:
	if hub_address == "" or connected:
		return
	_probe_timer -= delta
	if _probe_timer > 0.0:
		return
	_probe_timer = 2.0
	_udp.set_dest_address(hub_address, port)
	_udp.put_packet(JSON.stringify({"v": PROTOCOL_VERSION, "type": "connect"}).to_utf8_buffer())


func _handle(message: Dictionary, from_ip: String, from_port: int) -> void:
	last_problem = ""
	if not message.has("v"):
		last_problem = "Message had no \"v\" field; treated it as version 1"
	elif int(message.get("v")) != PROTOCOL_VERSION:
		last_problem = "Message is protocol version %s; the game expects %d" % [str(message.get("v")), PROTOCOL_VERSION]
		push_warning("UdpHitSource: " + last_problem)
		return
	last_message_ms = Time.get_ticks_msec()
	var type := str(message.get("type", ""))
	match type:
		"hello":
			_hub_ip = from_ip
			_hub_port = from_port
			_send({"type": "connect"})
			_mark_connected(str(message.get("hub", "hub")))
		"hit":
			_hub_ip = from_ip
			_hub_port = from_port
			_mark_connected(hub_name if hub_name != "" else "hub")
			_on_hit_message(message)
		"raw":
			_log_raw(message)
		_:
			last_problem = "Unknown message type \"%s\" (expected hello, hit or raw)" % type


func _on_hit_message(message: Dictionary) -> void:
	var id := int(message.get("id", -1))
	_send({"type": "ack", "id": id})
	if id >= 0:
		if id in _recent_ids:
			return  # A repeat (the hub resends if it misses our ack).
		_recent_ids.append(id)
		if _recent_ids.size() > 64:
			_recent_ids.pop_front()
	var wall_pos := Vector2(clampf(float(message.get("x", 0.5)), 0.0, 1.0),
		clampf(float(message.get("y", 0.5)), 0.0, 1.0))
	var force := float(message.get("force", default_force))
	_hit_bus.emit_hit(HitEvent.create(_to_screen(wall_pos), force, "hub_wifi"))


func _to_screen(wall_pos: Vector2) -> Vector2:
	if wall_to_screen.is_valid():
		return wall_to_screen.call(wall_pos)
	var size := get_viewport().get_visible_rect().size
	return Vector2(wall_pos.x * size.x, (1.0 - wall_pos.y) * size.y)


func _mark_connected(new_name: String) -> void:
	var was_connected := connected
	connected = true
	hub_name = new_name
	if not was_connected:
		hub_connected.emit(hub_name)


func _send(message: Dictionary) -> void:
	if _hub_ip == "":
		return
	message["v"] = PROTOCOL_VERSION
	_udp.set_dest_address(_hub_ip, _hub_port)
	_udp.put_packet(JSON.stringify(message).to_utf8_buffer())


func _log_raw(message: Dictionary) -> void:
	var is_new := not FileAccess.file_exists(raw_log_path)
	var file := FileAccess.open(raw_log_path, FileAccess.READ_WRITE if not is_new else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	if is_new:
		file.store_line("time_ms,id,dt_us,amp")
	var dt: Array = message.get("dt_us", [])
	var amp: Array = message.get("amp", [])
	file.store_line("%d,%d,%s,%s" % [Time.get_ticks_msec(), int(message.get("id", -1)),
		" ".join(dt.map(func(v: Variant) -> String: return str(v))),
		" ".join(amp.map(func(v: Variant) -> String: return str(v)))])
	file.close()
