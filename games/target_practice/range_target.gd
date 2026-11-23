class_name RangeTarget
extends Node3D
## One person-shaped target on the outdoor range, with its own way of moving:
##   POP_UP - rises out of the ground, stays up for `up_time`, sinks back.
##   MOVER  - rises, slides side to side along a rail, then sinks.
##   DEPTH  - rises, walks toward or away from the camera, then sinks.
##   PEEK   - slides out from behind cover, waits, ducks back (a few times).
## A friendly target is blue with a smiley face; hitting it is a penalty.
## The board shatters when a ball hits it, using the pre-broken shards from
## tools/blender/make_person_target.py.

enum Kind { POP_UP, MOVER, DEPTH, PEEK }

## Emitted when a ball breaks the board. `local_hit` is the hit position on
## the board (meters from its center), used for scoring.
signal shot(target: RangeTarget, local_hit: Vector3, world_hit: Vector3)
## Emitted when the target has gone away (shot, or its time ran out).
signal finished(target: RangeTarget)

# The silhouette, in meters from the board's center (match the Blender script).
const HALF_WIDTH := 0.3
const BOTTOM := -0.45
const TOP := 0.46
const THICKNESS := 0.12
const HEAD_CENTER := Vector2(0.0, 0.31)
const HEAD_RADIUS := 0.15
## The bullseye on the chest and its scoring rings (match person_target.gdshader).
const BULL_CENTER := Vector2(0.0, -0.12)
const BULL_RINGS := [0.05, 0.11, 0.17]

const RISE_TIME := 0.3
const SINK_DEPTH := 1.6  # How far below the ground a target hides.

var kind: Kind = Kind.POP_UP
var friendly := false
## Seconds a pop-up stays up; for movers, roughly how long they keep moving.
var up_time := 5.0
## Height of the board's center above the ground.
var board_height := 0.85
## MOVER: how far to each side it slides, and how fast (meters per second).
var rail_half_width := 3.5
var move_speed := 1.4
## DEPTH: where it starts and stops along the range (z, relative to its spot).
var depth_from := 0.0
var depth_to := -8.0
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
		Kind.DEPTH:
			_run_depth()
		Kind.PEEK:
			_run_peek()


## True while the board is showing above the ground (handy for tests).
func is_up() -> bool:
	return not _is_shot and _rig.position.y > -0.02


## The part of the screen this target will cover over its whole life (every
## spot it moves through), so the range can keep targets from overlapping.
## Works before the target is added to the scene.
func screen_footprint(camera: Camera3D, margin: float = 12.0) -> Rect2:
	var rect := Rect2()
	var first := true
	for offset in _path_offsets():
		for corner in [Vector2(-HALF_WIDTH, BOTTOM), Vector2(HALF_WIDTH, BOTTOM),
				Vector2(-HALF_WIDTH, TOP), Vector2(HALF_WIDTH, TOP)]:
			var world: Vector3 = position + offset + Vector3(corner.x, board_height + corner.y, 0.0)
			if camera.is_position_behind(world):
				continue
			var p := camera.unproject_position(world)
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect.grow(margin)


## Where the rig goes during this target's life (relative to its spot).
func _path_offsets() -> Array[Vector3]:
	match kind:
		Kind.MOVER:
			return [Vector3(-rail_half_width, 0, 0), Vector3(rail_half_width, 0, 0)]
		Kind.DEPTH:
			return [Vector3(0, 0, depth_from), Vector3(0, 0, depth_to)]
		Kind.PEEK:
			return [Vector3.ZERO, Vector3(peek_side * peek_distance, 0, 0)]
	return [Vector3.ZERO]


## Whether a spot on the board's face (meters from its center) is on the
## silhouette, not in the gap beside the head.
static func is_on_board(local: Vector2) -> bool:
	if local.distance_to(HEAD_CENTER) <= HEAD_RADIUS:
		return true
	return absf(local.x) <= HALF_WIDTH and local.y >= BOTTOM and local.y <= 0.16


func _build_post() -> void:
	var post := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var post_height := board_height + BOTTOM
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
	# Collision: a box for the torso and a disc for the head.
	var torso := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF_WIDTH * 2.0, 0.16 - BOTTOM, THICKNESS)
	torso.shape = box
	torso.position = Vector3(0.0, (0.16 + BOTTOM) / 2.0, 0.0)
	body.add_child(torso)
	var head := CollisionShape3D.new()
	var disc := CylinderShape3D.new()
	disc.radius = HEAD_RADIUS
	disc.height = THICKNESS
	head.shape = disc
	head.rotation_degrees.x = 90.0
	head.position = Vector3(HEAD_CENTER.x, HEAD_CENTER.y, 0.0)
	body.add_child(head)

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
	# The board is not parented to the moving rig: physics would keep pulling
	# it back. Instead it is placed where the rig says, every physics step.
	body.top_level = true
	add_child(body)
	_sync_body()


func _physics_process(_delta: float) -> void:
	_sync_body()


func _sync_body() -> void:
	if is_instance_valid(body) and not _is_shot:
		body.global_transform = _board_transform()


## Where the board should be right now: on top of the rig's post.
func _board_transform() -> Transform3D:
	var rig_xform := global_transform * _rig.transform if is_inside_tree() else transform * _rig.transform
	return rig_xform.translated_local(Vector3(0.0, board_height, 0.0))


func _on_broken(world_hit: Vector3) -> void:
	_is_shot = true
	if _tween != null:
		_tween.kill()
	shot.emit(self, body.to_local(world_hit), world_hit)
	# The board is gone; let the post drop away and tidy up shortly after.
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	t.tween_property(_rig, "position:y", -SINK_DEPTH, 0.5).set_delay(0.3)
	t.tween_callback(_finish)


# --- Movement ---------------------------------------------------------------

func _run_pop_up() -> void:
	_rig.position.y = -SINK_DEPTH
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_rise(_tween)
	_tween.tween_interval(up_time)
	_sink(_tween)
	_tween.tween_callback(_finish)


func _run_mover() -> void:
	_rig.position.y = -SINK_DEPTH
	var start := -rail_half_width if randf() < 0.5 else rail_half_width
	_rig.position.x = start
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_rise(_tween)
	var leg_time := (rail_half_width * 2.0) / move_speed
	var legs := maxi(1, int(ceil(up_time / leg_time)))
	var x := start
	for i in legs:
		x = -x
		_tween.tween_property(_rig, "position:x", x, leg_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sink(_tween)
	_tween.tween_callback(_finish)


func _run_depth() -> void:
	_rig.position = Vector3(0.0, -SINK_DEPTH, depth_from)
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_rise(_tween)
	var walk_time := absf(depth_to - depth_from) / move_speed
	_tween.tween_property(_rig, "position:z", depth_to, walk_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_interval(0.6)
	_sink(_tween)
	_tween.tween_callback(_finish)


func _run_peek() -> void:
	var hidden_x := _rig.position.x
	var shown_x := hidden_x + peek_side * peek_distance
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	for i in peek_count:
		_tween.tween_interval(randf_range(0.4, 1.2))
		_tween.tween_property(_rig, "position:x", shown_x, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(peek_time)
		_tween.tween_property(_rig, "position:x", hidden_x, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish)


func _rise(t: Tween) -> void:
	t.tween_property(_rig, "position:y", 0.0, RISE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _sink(t: Tween) -> void:
	t.tween_property(_rig, "position:y", -SINK_DEPTH, RISE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _finish() -> void:
	if is_queued_for_deletion():
		return
	finished.emit(self)
	queue_free()
