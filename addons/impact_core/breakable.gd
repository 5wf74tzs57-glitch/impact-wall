class_name Breakable
extends Node
## Makes its parent RigidBody3D shatter when something hits it hard enough.
##
## Add it as a child of a RigidBody3D. The pieces are worked out once, when
## the object is created, never at the moment of impact (phones can't afford
## that). On a hard hit the intact object is removed, the pieces burst away
## from the hit point, shrink and disappear after a couple of seconds.
##
## Pieces come from one of two places:
##   - `pieces_scene`: a model made ahead of time in Blender with a "Shards"
##     node whose children are the broken pieces, in place (realistic; see
##     tools/blender/make_target_shards.py). Used when set.
##   - Otherwise a grid of boxes cut from `size` (quick placeholder).

## Emitted when the object shatters, with the world position of the hit.
signal broken(hit_point: Vector3)

## Pre-broken pieces: a scene (e.g. a .glb from Blender) with a "Shards"
## node whose MeshInstance3D children are the pieces.
@export var pieces_scene: PackedScene
## Materials to put on the pieces' surfaces, by surface number (empty or
## null entries keep the model's own material). Lets one material, such as a
## bullseye, cover the outside of every shard.
@export var surface_materials: Array[Material] = []
## Size of the box being cut up for grid pieces, in meters.
@export var size: Vector3 = Vector3(0.6, 0.6, 0.15)
## Grid pieces only: how many along each side. Keep the total at 30 or fewer.
@export var grid: Vector3i = Vector3i(5, 5, 1)
## How hard a hit must shove this object to shatter it: its sudden change in
## momentum (mass x change in speed, in newton-seconds) while touching a
## moving object. For scale: a 0.5 kg ball at 14 m/s gives a 1 kg target
## about 3; a gentle nudge stays well under 1.
@export var min_break_impulse: float = 1.5
## How hard the pieces burst outward from the hit point (meters per second).
@export var burst_speed: float = 3.0
## How much of the hitting object's speed the pieces carry on (0 to 1).
@export_range(0.0, 1.0) var carry_through: float = 0.25
## Seconds before the pieces are gone (they shrink over the last third).
@export var piece_lifetime: float = 2.0
## Color for every piece, unless `piece_color` (below) is set.
@export var default_color: Color = Color(0.9, 0.9, 0.9)

## Optional: a function (local_position: Vector3) -> Color that picks each
## piece's color from where it sits on the object, e.g. to keep a bullseye.
var piece_color: Callable

var _body: RigidBody3D
var _pieces: Array[Dictionary] = []  # {xform: Transform3D, mesh: Mesh, shape: Shape3D}

## Pieces read from each pieces_scene, so the work is done once per model,
## not once per target.
static var _scene_cache := {}
var _is_broken := false
var _last_velocity := Vector3.ZERO


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("Breakable must be a child of a RigidBody3D.")
		return
	_body.contact_monitor = true
	# Leave room for the hitting object: resting on a shelf alone can use 4.
	_body.max_contacts_reported = maxi(_body.max_contacts_reported, 8)
	if pieces_scene != null:
		_pieces = _pieces_from_scene(pieces_scene)
	else:
		_prepare_grid_pieces()
	if _pieces.size() > 30:
		push_warning("Breakable: %d pieces is a lot for a phone; aim for 30 or fewer." % _pieces.size())


## Shatter right now, as if hit at `hit_point` by something moving at `hit_velocity`.
func shatter(hit_point: Vector3, hit_velocity: Vector3 = Vector3.ZERO) -> void:
	if _is_broken or _body == null:
		return
	_is_broken = true
	# Adding physics bodies inside a collision callback isn't allowed, so wait
	# until the physics step has finished.
	_spawn_pieces.call_deferred(hit_point, hit_velocity)


func _physics_process(_delta: float) -> void:
	# How hard were we just shoved? Measure our own sudden change in momentum.
	# (Comparing the ball's speed doesn't work: by the time a collision is
	# reported, the ball has already bounced and slowed down.)
	if _is_broken or _body == null:
		return
	var shove := (_body.linear_velocity - _last_velocity).length() * _body.mass
	_last_velocity = _body.linear_velocity
	if shove < min_break_impulse:
		return
	# Only a moving object counts, so landing on the floor doesn't break us.
	var state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	if state == null:
		return
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as RigidBody3D
		if other != null:
			shatter(state.get_contact_collider_position(i), other.linear_velocity)
			return


static func _pieces_from_scene(scene: PackedScene) -> Array[Dictionary]:
	var key := scene.resource_path if scene.resource_path != "" else str(scene.get_instance_id())
	if _scene_cache.has(key):
		return _scene_cache[key]
	var pieces: Array[Dictionary] = []
	var root := scene.instantiate()
	var shards_root := root.find_child("Shards", true, false)
	if shards_root == null:
		push_error("Breakable: %s has no node named \"Shards\"." % key)
	else:
		for node in shards_root.get_children():
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			pieces.append({
				"xform": _transform_to_root(mi, root),
				"mesh": mi.mesh,
				"shape": mi.mesh.create_convex_shape(true, false),
			})
	root.free()
	_scene_cache[key] = pieces
	return pieces


static func _transform_to_root(node: Node3D, root: Node) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


func _prepare_grid_pieces() -> void:
	var cell := Vector3(size.x / grid.x, size.y / grid.y, size.z / grid.z)
	var materials := {}
	for ix in grid.x:
		for iy in grid.y:
			for iz in grid.z:
				var offset := Vector3(
					(ix + 0.5) * cell.x - size.x / 2.0,
					(iy + 0.5) * cell.y - size.y / 2.0,
					(iz + 0.5) * cell.z - size.z / 2.0)
				# Slightly uneven pieces look less like a grid.
				var piece_size := cell * Vector3(randf_range(0.8, 1.0), randf_range(0.8, 1.0), 1.0)
				var color: Color = default_color
				if piece_color.is_valid():
					color = piece_color.call(offset)
				if not materials.has(color):
					var mat := StandardMaterial3D.new()
					mat.albedo_color = color
					materials[color] = mat
				var mesh := BoxMesh.new()
				mesh.size = piece_size
				mesh.material = materials[color]
				var shape := BoxShape3D.new()
				shape.size = piece_size
				_pieces.append({"xform": Transform3D(Basis(), offset), "mesh": mesh, "shape": shape})


func _spawn_pieces(hit_point: Vector3, hit_velocity: Vector3) -> void:
	if not is_instance_valid(_body):
		return
	var world := _body.get_parent()
	var body_xform := _body.global_transform
	var body_velocity := _body.linear_velocity
	var piece_mass := _body.mass / maxf(_pieces.size(), 1.0)

	var debris := Node3D.new()
	debris.name = "Debris"
	world.add_child(debris)

	for piece in _pieces:
		var rb := RigidBody3D.new()
		rb.mass = piece_mass
		var col := CollisionShape3D.new()
		col.shape = piece["shape"]
		rb.add_child(col)
		var mi := MeshInstance3D.new()
		mi.mesh = piece["mesh"]
		for s in mini(surface_materials.size(), mi.mesh.get_surface_count()):
			if surface_materials[s] != null:
				mi.set_surface_override_material(s, surface_materials[s])
		rb.add_child(mi)
		debris.add_child(rb)
		rb.global_transform = body_xform * (piece["xform"] as Transform3D)

		var away := rb.global_position - hit_point
		var push := away.normalized() if away.length() > 0.001 else Vector3.UP
		rb.linear_velocity = body_velocity + hit_velocity * carry_through \
			+ push * burst_speed * randf_range(0.7, 1.3)
		rb.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))

		var shrink := mi.create_tween()
		shrink.tween_interval(piece_lifetime * 2.0 / 3.0)
		shrink.tween_property(mi, "scale", Vector3.ZERO, piece_lifetime / 3.0)

	debris.get_tree().create_timer(piece_lifetime + 0.1).timeout.connect(debris.queue_free)
	broken.emit(hit_point)
	_body.queue_free()
