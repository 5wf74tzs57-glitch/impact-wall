class_name Breakable
extends Node
## Makes its parent RigidBody3D shatter when something hits it hard enough.
##
## Add it as a child of a RigidBody3D. The pieces are worked out once, when
## the object is created, never at the moment of impact (phones can't afford
## that). On a hard hit the intact object is removed, the pieces burst away
## from the hit point, shrink and disappear after a couple of seconds.
##
## The pieces here are a grid of boxes cut from `size`. Later they can come
## from meshes pre-fractured in Blender (Cell Fracture) or VoronoiShatter,
## without changing how games use this node.

## Emitted when the object shatters, with the world position of the hit.
signal broken(hit_point: Vector3)

## Size of the box being cut up, in meters (match the collision shape).
@export var size: Vector3 = Vector3(0.6, 0.6, 0.15)
## How many pieces along each side. Keep the total at about 30 or fewer.
@export var grid: Vector3i = Vector3i(5, 5, 1)
## A hit must be at least this fast (meters per second) to shatter it.
@export var min_break_speed: float = 6.0
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
var _pieces: Array[Dictionary] = []  # {offset: Vector3, mesh: BoxMesh, shape: BoxShape3D}
var _is_broken := false


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("Breakable must be a child of a RigidBody3D.")
		return
	if grid.x * grid.y * grid.z > 30:
		push_warning("Breakable: %d pieces is a lot for a phone; aim for 30 or fewer." % (grid.x * grid.y * grid.z))
	_body.contact_monitor = true
	_body.max_contacts_reported = maxi(_body.max_contacts_reported, 4)
	_body.body_entered.connect(_on_body_entered)
	_prepare_pieces()


## Shatter right now, as if hit at `hit_point` by something moving at `hit_velocity`.
func shatter(hit_point: Vector3, hit_velocity: Vector3 = Vector3.ZERO) -> void:
	if _is_broken or _body == null:
		return
	_is_broken = true
	# Adding physics bodies inside a collision callback isn't allowed, so wait
	# until the physics step has finished.
	_spawn_pieces.call_deferred(hit_point, hit_velocity)


func _on_body_entered(other: Node) -> void:
	var other_body := other as RigidBody3D
	if other_body == null:
		return
	var relative := other_body.linear_velocity - _body.linear_velocity
	if relative.length() >= min_break_speed:
		shatter(other_body.global_position, other_body.linear_velocity)


func _prepare_pieces() -> void:
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
				_pieces.append({"offset": offset, "mesh": mesh, "shape": shape})


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
		rb.add_child(mi)
		debris.add_child(rb)
		rb.global_transform = body_xform.translated_local(piece["offset"])

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
