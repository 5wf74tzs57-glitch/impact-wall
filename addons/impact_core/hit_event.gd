class_name HitEvent
extends RefCounted
## One impact, in a form every game understands, whatever produced it
## (a tap on the screen, a replayed log, or the ESP32 hub).

## Where the hit landed, in screen (viewport) pixels.
var screen_pos: Vector2
## How hard the hit was, from 0.0 (softest) to 1.0 (hardest).
var force: float
## When the hit happened, in milliseconds (Time.get_ticks_msec() clock).
var time_ms: int
## What produced the hit, e.g. "tap", "replay", "hub_wifi".
var source: String


static func create(p_screen_pos: Vector2, p_force: float, p_source: String, p_time_ms: int = -1) -> HitEvent:
	var event := HitEvent.new()
	event.screen_pos = p_screen_pos
	event.force = clampf(p_force, 0.0, 1.0)
	event.source = p_source
	event.time_ms = p_time_ms if p_time_ms >= 0 else Time.get_ticks_msec()
	return event
