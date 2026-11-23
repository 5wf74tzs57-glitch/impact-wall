class_name TapHitSource
extends Node
## Turns a tap on the screen (or a mouse click on a computer) into a hit.
## This is the "no hardware" source: it lets us build and playtest games
## before the hub is connected.

## Taps can't measure force, so every tap uses this value (0.0 to 1.0).
@export_range(0.0, 1.0) var tap_force: float = 0.7
## Add a little random variation so taps feel less mechanical.
@export_range(0.0, 0.5) var force_jitter: float = 0.1


func _unhandled_input(input_event: InputEvent) -> void:
	# Mouse clicks also arrive as touches (Project Settings: emulate touch from mouse).
	var touch := input_event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return
	var force := tap_force + randf_range(-force_jitter, force_jitter)
	get_node("/root/HitBus").emit_hit(HitEvent.create(touch.position, force, "tap"))
	get_viewport().set_input_as_handled()
