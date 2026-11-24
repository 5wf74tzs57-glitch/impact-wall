class_name RangeTarget
extends Node3D
## One cartoon person target on the outdoor range, with its own way of moving:
##   POP_UP - rises out of the ground, stays up for `up_time`, sinks back.
##   MOVER  - rises, slides side to side along a rail, then sinks.
##   DEPTH  - rises, walks toward or away from the camera, then sinks.
##   PEEK   - slides out from behind cover, waits, ducks back (a few times).
## A friendly target is blue with a smiley face; hitting it is a penalty.
##
## The model is Tim's cartoon target (assets/source/targets.blend), split into
## Head, Left, Center and Right, with pre-broken shards for each part made by
## tools/blender/make_cartoon_shards.py. Where the ball lands decides what
## breaks: the head knocks off just the head, the outer sides break off that
## side, and the inner three chest rings or the middle shatter everything.
## If only part breaks, the rest of the target tips over backwards.

enum Kind { POP_UP, MOVER, DEPTH, PEEK }

## Emitted when a ball breaks the board. `local_hit` is the hit position on
## the board (meters from its center), used for scoring.
signal shot(target: RangeTarget, local_hit: Vector3, world_hit: Vector3)
## Emitted when the target has gone away (shot, or its time ran out).
signal finished(target: RangeTarget)

# The silhouette, in meters from the board's center (measured from the model).
const HALF_WIDTH := 0.307
const BOTTOM := -0.461
const TOP := 0.461
const THICKNESS := 0.12
const NECK_Y := 0.173  # Where the head meets the torso.
const SIDE_X := 0.144  # Where the side parts meet the center.
const HEAD_CENTER := Vector2(0.0, 0.314)
const HEAD_RADIUS := 0.147
## The artwork's bullseyes, measured from the texture: ring edges from the
## center outward (meters). Chest rings are worth 5, 4, 3, 2, 1; head rings
## 5, 4, 3 (the rest of the head 2).
const BULL_CENTER := Vector2(0.0, -0.157)
const CHEST_RINGS := [0.055, 0.108, 0.16, 0.212, 0.262]
const HEAD_RINGS := [0.031, 0.065, 0.095]
## Hits this close to the chest bullseye (the 5, 4 and 3 rings) shatter it all.
const FULL_SHATTER_RADIUS := 0.16
const MODEL_PARTS := ["Head", "Left", "Center", "Right"]

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
var breakable: Breakable
var _rig: Node3D
var _tween: Tween
var _is_shot := false

## Collision shapes made from the model's parts, once per model.
static var _part_shapes := {}


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
	if local.y > NECK_Y:
		return local.distance_to(HEAD_CENTER) <= HEAD_RADIUS
	return absf(local.x) <= HALF_WIDTH and local.y >= BOTTOM


## Which parts a hit at this spot breaks (an empty list breaks everything).
static func parts_for_hit(local: Vector3) -> Array[String]:
	var p := Vector2(local.x, local.y)
	if p.y > NECK_Y:
		return ["Head"]
	if p.distance_to(BULL_CENTER) <= FULL_SHATTER_RADIUS:
		return []
	if p.x > SIDE_X:
		return ["Right"]
	if p.x < -SIDE_X:
		return ["Left"]
	return []


## Points for a hit at this spot, before distance and moving bonuses.
static func zone_points(local: Vector2) -> int:
	if local.y > NECK_Y:
		var rh := local.distance_to(HEAD_CENTER)
		for i in HEAD_RINGS.size():
			if rh <= HEAD_RINGS[i]:
				return 5 - i
		return 2
	var r := local.distance_to(BULL_CENTER)
	for i in CHEST_RINGS.size():
		if r <= CHEST_RINGS[i]:
			return 5 - i
	return 1


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
	var visual := model.instantiate() as Node3D
	for shards in visual.find_children("Shards*", "", true, false):
		shards.free()  # Only used when a part breaks.
	# One collision shape per part, made from the part's own mesh, so the hit
	# area is exactly the drawn silhouette.
	for part_name in MODEL_PARTS:
		var part := visual.find_child("Part_" + part_name, true, false) as MeshInstance3D
		if part == null:
			push_error("RangeTarget: the model has no Part_%s." % part_name)
			continue
		if friendly:
			part.set_surface_override_material(0, face_material)
		var hit := CollisionShape3D.new()
		hit.name = "Hit_" + part_name
		hit.shape = _shape_for(part.mesh)
		hit.transform = part.transform
		body.add_child(hit)
	body.add_child(visual)
	breakable = Breakable.new()
	breakable.pieces_scene = model
	if friendly:
		var mats: Array[Material] = [face_material]
		breakable.surface_materials = mats
	breakable.face_z = THICKNESS / 2.0
	breakable.parts_for_hit = RangeTarget.parts_for_hit
	breakable.debris_parent = get_parent()  # Pieces outlive this target.
	breakable.parts_broken.connect(_on_parts_broken)
	body.add_child(breakable)
	# The board is not parented to the moving rig: physics would keep pulling
	# it back. Instead it is placed where the rig says, every physics step.
	body.top_level = true
	add_child(body)
	_sync_body()


static func _shape_for(mesh: Mesh) -> Shape3D:
	if not _part_shapes.has(mesh):
		_part_shapes[mesh] = mesh.create_convex_shape(true, false)
	return _part_shapes[mesh]


func _physics_process(_delta: float) -> void:
	_sync_body()


func _sync_body() -> void:
	if is_instance_valid(body):
		body.global_transform = _board_transform()


## Where the board should be right now: on top of the rig's post.
func _board_transform() -> Transform3D:
	var rig_xform := global_transform * _rig.transform if is_inside_tree() else transform * _rig.transform
	return rig_xform.translated_local(Vector3(0.0, board_height, 0.0))


func _on_parts_broken(_parts: Array[String], local_hit: Vector3, all_gone: bool) -> void:
	if _is_shot:
		return  # Already scored; it's on its way down.
	_is_shot = true
	if _tween != null:
		_tween.kill()
	shot.emit(self, local_hit, body.to_global(local_hit))
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	if not all_gone:
		# Part of it is left: tip over backwards, then sink.
		t.tween_property(_rig, "rotation:x", -1.35, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_interval(0.4)
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
