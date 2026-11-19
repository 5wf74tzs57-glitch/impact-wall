class_name HubOverlay
extends CanvasLayer
## Press H to show what the game knows about the hub connection: this
## device's network address, whether anything has arrived, the last message,
## and what (if anything) was wrong with it. For getting a real hub talking.
## Troubleshooting steps: docs/hub_troubleshooting.md

## The hub source to report on.
var source: UdpHitSource

var _panel: PanelContainer
var _text: Label
var _refresh := 0.0


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 0.9)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(24.0, 80.0)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 22)
	_panel.add_child(_text)
	add_child(_panel)
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_H:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_panel.visible = not _panel.visible
	_update_text()


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_update_text()


func _update_text() -> void:
	if source == null:
		_text.text = "No hub source"
		return
	var lines: Array[String] = []
	lines.append("HUB INFO   (press H to close)")
	lines.append("")
	lines.append("This device:   %s" % ", ".join(local_addresses()))
	lines.append("Listening on:  UDP port %d  %s" % [source.port, "OK" if source.listening else "FAILED"])
	if source.hub_address != "":
		lines.append("Asking hub at: %s" % source.hub_address)
	lines.append("Connected:     %s" % ("yes (%s)" % source.hub_name if source.connected else "no"))
	lines.append("Packets in:    %d" % source.packets_received)
	if source.packets_received > 0:
		var ago := (Time.get_ticks_msec() - source.last_message_ms) / 1000.0 if source.last_message_ms > 0 else -1.0
		lines.append("Last from:     %s%s" % [source.last_packet_from, "   (%.0f s ago)" % ago if ago >= 0.0 else ""])
		lines.append("Last packet:   %s" % source.last_packet_text.left(90))
	if source.last_problem != "":
		lines.append("")
		lines.append("Problem: " + source.last_problem)
	if source.packets_received == 0:
		lines.append("")
		lines.append("Nothing has arrived yet. Check:")
		lines.append(" - hub and this device on the same Wi-Fi (not a guest network)")
		lines.append(" - firewall allows this game on private networks")
		lines.append(" - hub sends to port %d (broadcast or this device's address)" % source.port)
	_text.text = "\n".join(lines)


## This device's IPv4 addresses on the local network.
static func local_addresses() -> Array[String]:
	var result: Array[String] = []
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	if result.is_empty():
		result.append("(no network)")
	return result
