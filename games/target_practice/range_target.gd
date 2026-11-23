class_name RangeTarget
extends Node3D
## One target on the outdoor range, with its own way of moving:
##   POP_UP - rises out of the ground, stays up for `up_time`, sinks back.
##   MOVER  - rises, slides back and forth along a rail, then sinks.
##   PEEK   - slides out from behind cover, waits, ducks back (a few times).
## A friendly target looks different (a smiley face); hitting it is a penalty.
## The board shatters when a ball hits it, using the pre-broken shards.

enum Kind { POP_UP, MOVER, PEEK }

## Emitted when a ball breaks the board. `local_hit` is the hit position on
## the board (meters from its center), used for ring scoring.
signal shot(target: RangeTarget, local_hit: Vector3, world_hit: Vector3)
## Emitted when the target has gone away (shot, or its time ran out).
signal finished(target: RangeTarget)

const BOARD_SIZE := Vector3(0.6, 0.6, 0.15)
const RISE_TIME := 0.3
const SINK_DEPTH := 1.4  # How far below the ground a pop-up hides.

var kind: Kind = Kind.POP_UP
var friendly := false
## Seconds a pop-up (or mover) stays up. Peek targets use `peek_time` instead.
var up_time := 5.0
## Height of the board's center above the ground.
var board_height := 0.9
## MOVER: how far to each side it slides, and how fast (meters per second).
var rail_half_width := 3.5
var move_speed := 1.4
## PEEK: which way it slides out from cover (+1 right, -1 left), how far,
## how long it stays out, and how many times it peeks.
var peek_side := 1.0
var peek_distance := 0.95
var peek_time := 2.5
var peek_count := 2
## Set by whoever creates the target.
var model: PackedScene
var face_material: Material

var body: RigidBody3D
var _rig: Node3D
var _tween: Tween
var _is_shot := false


func _ready() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	_build_post()
	_build_board()
	match kind:
		Kind.POP_UP:
			_run_pop_up()
		Kind.MOVER:
			_run_mover()
		Kind.PEEK:
			_run_peek()


## True while the board is showing above the ground (handy for tests).
func is_up() -> bool:
	return not _is_shot and _rig.position.y > -0.02


func _build_post() -> void:
	var post := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var post_height := board_height - BOARD_SIZE.y / 2.0
	mesh.size = Vector3(0.06, post_height, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.24, 0.16)
	mesh.material = mat
	post.mesh = mesh
	post.position = Vector3(0.0, post_height / 2.0, 0.0)
	_rig.add_child(post)


func _build_board() -> void:
	body = RigidBody3D.new()
	body.freeze = true  # Moved by this script, not by gravity.
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.mass = 1.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BOARD_SIZE
	shape.shape = box
	body.add_child(shape)
	var visual := model.instantiate() as Node3D
	var shards := visual.find_child("Shards", true, false)
	if shards != null:
		shards.free()  # Only used when it breaks.
	var board := visual.find_child("Intact", true, false) as MeshInstance3D
	if board != null:
		board.set_surface_override_material(0, face_material)
	body.add_child(visual)
	var breakable := Breakable.new()
	breakable.pieces_scene = model
	var mats: Array[Material] = [face_material]
	breakable.surface_materials = mats
	breakable.debris_parent = get_parent()  # Pieces outlive this target.
	breakable.broken.connect(_on_broken)
	body.add_child(breakable)
	body.position = Vector3(0.0, board_height, 0.0)
	_rig.add_child(body)


func _on_broken(world_hit: Vector3) -> void:
	_is_shot = true
	if _tween != null:
		_tween.kill()
	shot.emit(self, body.to_local(world_hit), world_hit)
	# The board is gone; let the post drop away and tidy up shortly after.
	var t := create_tween()
	t.tween_property(_rig, "position:y", -SINK_DEPTH, 0.5).set_delay(0.3)
	t.tween_callback(_finish)


# --- Movement ---------------------------------------------------------------

func _run_pop_up() -> void:
	_rig.position.y = -SINK_DEPTH
	_tween = create_tween()
	_rise(_tween)
	_hold(_tween, up_time)
	_sink(_tween)
	_tween.tween_callback(_finish)


func _run_mover() -> void:
	_rig.position.y = -SINK_DEPTH
	var start := -rail_half_width if randf() < 0.5 else rail_half_width
	_rig.position.x = start
	_tween = create_tween()
	_rise(_tween)
	# Slide across and back until up_time is used up.
	var leg_time := (rail_half_width * 2.0) / move_speed
	var legs := maxi(1, int(ceil(up_time / leg_time)))
	var x := start
	for i in legs:
		x = -x
		_tween.tween_property(_rig, "position:x", x, leg_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sink(_tween)
	_tween.tween_callback(_finish)


func _run_peek() -> void:
	var hidden_x := _rig.position.x
	var shown_x := hidden_x + peek_side * peek_distance
	_tween = create_tween()
	for i in peek_count:
		_tween.tween_interval(randf_range(0.4, 1.2))
		_tween.tween_property(_rig, "position:x", shown_x, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_hold(_tween, peek_time)
		_tween.tween_property(_rig, "position:x", hidden_x, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish)


func _rise(t: Tween) -> void:
	t.tween_property(_rig, "position:y", 0.0, RISE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _sink(t: Tween) -> void:
	t.tween_property(_rig, "position:y", -SINK_DEPTH, RISE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _hold(t: Tween, seconds: float) -> void:
	t.tween_interval(seconds)


func _finish() -> void:
	if is_queued_for_deletion():
		return
	finished.emit(self)
	queue_free()
