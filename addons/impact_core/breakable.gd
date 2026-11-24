class_name Breakable
extends Node
## Makes its parent RigidBody3D shatter when something hits it hard enough,
## either all at once or one part at a time.
##
## Add it as a child of a RigidBody3D. The pieces are worked out once, when
## the object is created, never at the moment of impact (phones can't afford
## that). On a hit the pieces burst away from the hit point, shrink and
## disappear after a couple of seconds.
##
## Pieces come from one of two places:
##   - `pieces_scene`: a model made ahead of time in Blender. Either one node
##     named "Shards" (the whole object breaks at once; see
##     tools/blender/make_target_shards.py), or one "Shards_<Part>" node per
##     part (see tools/blender/make_cartoon_shards.py), so a hit can break
##     just one part. For parts, the body should hold a visual named
##     "Part_<Part>" and a collision shape named "Hit_<Part>" for each part;
##     those are hidden and switched off when that part breaks.
##   - Otherwise a grid of boxes cut from `size` (quick placeholder).

## Emitted on every break, with the world position of the hit.
signal broken(hit_point: Vector3)
## Emitted on every break: which parts broke ("" = the whole object when it
## has no parts), where it was hit (in the body's own coordinates), and
## whether anything is left.
signal parts_broken(parts: Array[String], local_hit: Vector3, all_gone: bool)

## Pre-broken pieces (see above).
@export var pieces_scene: PackedScene
## Materials to put on the pieces' surfaces, by surface number (empty or
## null entries keep the model's own material).
@export var surface_materials: Array[Material] = []
## Size of the box being cut up for grid pieces, in meters.
@export var size: Vector3 = Vector3(0.6, 0.6, 0.15)
## Grid pieces only: how many along each side. Keep the total at 30 or fewer.
@export var grid: Vector3i = Vector3i(5, 5, 1)
## How hard a hit must shove this object to shatter it (unfrozen bodies):
## its sudden change in momentum (mass x change in speed, in newton-seconds)
## while touching a moving object. A 0.5 kg ball at 14 m/s gives a 1 kg
## target about 3; a gentle nudge stays well under 1.
@export var min_break_impulse: float = 1.5
## How hard the pieces burst outward from the hit point (meters per second).
@export var burst_speed: float = 3.0
## How much of the hitting object's speed the pieces carry on (0 to 1).
@export_range(0.0, 1.0) var carry_through: float = 0.25
## Seconds before the pieces are gone (they shrink over the last third).
@export var piece_lifetime: float = 2.0
## Distance from the body's center to its front face (local +Z), used to find
## exactly where a thrown ball crossed the face.
@export var face_z: float = 0.06
## Where the flying pieces are added. Defaults to the object's parent; set it
## when that parent may disappear soon after the hit (e.g. a moving rig).
var debris_parent: Node
## Parts mode: a function (local_hit: Vector3) -> Array[String] choosing which
## parts a hit breaks. An empty result breaks everything that's left.
var parts_for_hit: Callable
## Color for every grid piece, unless `piece_color` (below) is set.
@export var default_color: Color = Color(0.9, 0.9, 0.9)
## Optional: a function (local_position: Vector3) -> Color for grid pieces.
var piece_color: Callable

var _body: RigidBody3D
## Pieces by part name ("" when the object has no parts).
var _pieces := {}
var _remaining: Array[String] = []
var _balls_seen := {}
var _last_velocity := Vector3.ZERO

## Pieces read from each pieces_scene, so the work is done once per model,
## not once per target.
static var _scene_cache := {}


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
		_pieces = {"": _grid_pieces()}
	for part in _pieces:
		_remaining.append(part)
	var count := 0
	for part in _pieces:
		count += (_pieces[part] as Array).size()
	if count > 30:
		push_warning("Breakable: %d pieces is a lot for a phone; aim for 30 or fewer." % count)


## True once nothing is left.
func is_broken() -> bool:
	return _remaining.is_empty()


## Names of the parts not yet broken ("" for an object without parts).
func remaining_parts() -> Array[String]:
	return _remaining.duplicate()


## Break now, as if hit at `hit_point` (world) by something moving at
## `hit_velocity`. `local_hit` (body coordinates) picks the parts; leave it
## out to use `hit_point`.
func shatter(hit_point: Vector3, hit_velocity: Vector3 = Vector3.ZERO, local_hit: Variant = null) -> void:
	if _remaining.is_empty() or _body == null:
		return
	var local: Vector3 = local_hit if local_hit != null else _body.to_local(hit_point)
	var parts: Array[String] = []
	if parts_for_hit.is_valid():
		for p in parts_for_hit.call(local):
			if String(p) in _remaining:
				parts.append(String(p))
	if parts.is_empty():
		parts = _remaining.duplicate()
	for p in parts:
		_remaining.erase(p)
	# Adding physics bodies inside a collision callback isn't allowed, so wait
	# until the physics step has finished.
	_spawn_pieces.call_deferred(parts, hit_point, hit_velocity, local)


func _physics_process(_delta: float) -> void:
	if _remaining.is_empty() or _body == null:
		return
	if _body.freeze:
		_check_ball_contacts()  # Moved by script, so it can't be "shoved".
		return
	# How hard were we just shoved? Measure our own sudden change in momentum.
	# (Comparing the ball's speed doesn't work: by the time a collision is
	# reported, the ball has already bounced and slowed down.)
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


## For targets moved by script (frozen bodies): a thrown ball touching it
## breaks it (once per ball).
func _check_ball_contacts() -> void:
	var state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	if state == null:
		return
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as RigidBody3D
		if other == null or not other.is_in_group(ImpactBridge.BALL_GROUP):
			continue
		if _balls_seen.has(other.get_instance_id()):
			continue
		_balls_seen[other.get_instance_id()] = true
		var contact := state.get_contact_collider_position(i)
		shatter(contact, other.linear_velocity, _exact_face_hit(other, contact))
		return


## Where the ball really struck the front face (body coordinates). Thrown
## balls fly straight until their first contact, so it's where their path
## crosses the face; the contact point the physics engine reports drifts a
## little once the ball starts to bounce.
func _exact_face_hit(ball: Node3D, contact: Vector3) -> Vector3:
	if not ball.has_meta(ImpactBridge.PATH_META):
		return _body.to_local(contact)
	var path: Array = ball.get_meta(ImpactBridge.PATH_META)
	var inv := _body.global_transform.affine_inverse()
	var start: Vector3 = inv * (path[0] as Vector3)
	var direction: Vector3 = inv.basis * (path[1] as Vector3)
	if absf(direction.z) < 0.001:
		return _body.to_local(contact)
	return start + direction * ((face_z - start.z) / direction.z)


static func _pieces_from_scene(scene: PackedScene) -> Dictionary:
	var key := scene.resource_path if scene.resource_path != "" else str(scene.get_instance_id())
	if _scene_cache.has(key):
		return _scene_cache[key]
	var groups := {}
	var root := scene.instantiate()
	for node in root.find_children("Shards*", "", true, false):
		var part := ""
		if node.name.begins_with("Shards_"):
			part = node.name.substr(7)
		elif node.name != "Shards":
			continue
		var pieces: Array[Dictionary] = []
		for child in node.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			pieces.append({
				"xform": _transform_to_root(mi, root),
				"mesh": mi.mesh,
				"shape": mi.mesh.create_convex_shape(true, false),
			})
		groups[part] = pieces
	if groups.is_empty():
		push_error("Breakable: %s has no \"Shards\" or \"Shards_<Part>\" node." % key)
	root.free()
	_scene_cache[key] = groups
	return groups


static func _transform_to_root(node: Node3D, root: Node) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


func _grid_pieces() -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
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
				pieces.append({"xform": Transform3D(Basis(), offset), "mesh": mesh, "shape": shape})
	return pieces


func _spawn_pieces(parts: Array[String], hit_point: Vector3, hit_velocity: Vector3, local_hit: Vector3) -> void:
	if not is_instance_valid(_body):
		return
	var world := debris_parent if is_instance_valid(debris_parent) else _body.get_parent()
	var body_xform := _body.global_transform
	var body_velocity := _body.linear_velocity
	var total := 0
	for part in _pieces:
		total += (_pieces[part] as Array).size()
	var piece_mass := _body.mass / maxf(total, 1.0)

	var debris := Node3D.new()
	debris.name = "Debris"
	world.add_child(debris)

	for part in parts:
		# Hide the intact part and switch off its collision.
		if part != "":
			var visual := _body.find_child("Part_" + part, true, false) as Node3D
			if visual != null:
				visual.visible = false
			var hit_shape := _body.find_child("Hit_" + part, true, false) as CollisionShape3D
			if hit_shape != null:
				hit_shape.disabled = true
		for piece in _pieces.get(part, []):
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
	var all_gone := _remaining.is_empty()
	broken.emit(hit_point)
	parts_broken.emit(parts, local_hit, all_gone)
	if all_gone:
		_body.queue_free()
