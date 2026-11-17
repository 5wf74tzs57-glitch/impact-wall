extends Node3D
## Target Practice, first test scene (Benchmark 4).
##
## Tap or click to throw a virtual ball into the room. Shatter the target
## (or knock it off its shelf) to score; a new target appears somewhere else.
## The scene is built in code so it is easy to read and change.

const SHELF_Z := -6.0
const SHELF_TOP := 1.0
const SHELF_WIDTH := 4.0
const TARGET_SIZE := Vector3(0.6, 0.6, 0.15)
const RESPAWN_DELAY := 1.2
const RED := Color(0.9, 0.2, 0.18)
const WHITE := Color(0.95, 0.95, 0.92)
## Bullseye ring edges, from the outside in (meters from the center).
const RING_RADII := [0.27, 0.18, 0.09]

var _camera: Camera3D
var _target: RigidBody3D
var _target_knocked := false
var _score := 0
var _throws := 0
var _score_label: Label
var _ui_layer: CanvasLayer


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_ui()

	var tap_source := TapHitSource.new()
	add_child(tap_source)

	var bridge := ImpactBridge.new()
	bridge.camera = _camera
	add_child(bridge)
	bridge.ball_launched.connect(_on_ball_launched)

	_spawn_target()


func _physics_process(_delta: float) -> void:
	# Backup scoring: a soft hit can knock the target over without shattering it.
	if not is_instance_valid(_target) or _target_knocked:
		return
	var fell := _target.global_position.y < SHELF_TOP - 0.2
	var tipped := _target.global_transform.basis.y.dot(Vector3.UP) < 0.5
	if fell or tipped:
		_score_hit(_target.global_position)


func _on_target_broken(hit_point: Vector3) -> void:
	_target = null  # The Breakable removes the target itself.
	_score_hit(hit_point)


func _score_hit(world_point: Vector3) -> void:
	if _target_knocked:
		return
	_target_knocked = true
	_score += 1
	_update_score()
	_show_score_pop(world_point)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_spawn_target)


func _on_ball_launched(_ball: RigidBody3D, _event: HitEvent) -> void:
	_throws += 1
	_update_score()


func _spawn_target() -> void:
	if is_instance_valid(_target):
		_target.queue_free()
	_target = RigidBody3D.new()
	_target.mass = 1.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = TARGET_SIZE
	shape.shape = box
	_target.add_child(shape)
	_target.add_child(_make_target_mesh())
	var breakable := Breakable.new()
	breakable.size = TARGET_SIZE
	breakable.grid = Vector3i(5, 5, 1)
	breakable.piece_color = _bullseye_color
	breakable.broken.connect(_on_target_broken)
	_target.add_child(breakable)
	add_child(_target)
	var x := randf_range(-SHELF_WIDTH / 2.0 + 0.5, SHELF_WIDTH / 2.0 - 0.5)
	_target.global_position = Vector3(x, SHELF_TOP + TARGET_SIZE.y / 2.0, SHELF_Z)
	_target_knocked = false


func _make_target_mesh() -> Node3D:
	# A board with a red-and-white bullseye on the front.
	var root := Node3D.new()
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = TARGET_SIZE
	board_mesh.material = _material(WHITE)
	board.mesh = board_mesh
	root.add_child(board)
	for i in RING_RADII.size():
		var ring := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = RING_RADII[i]
		disc.bottom_radius = RING_RADII[i]
		disc.height = 0.01
		disc.material = _material(RED if i % 2 == 0 else WHITE)
		ring.mesh = disc
		ring.rotation_degrees.x = 90.0
		ring.position.z = TARGET_SIZE.z / 2.0 + 0.005 + i * 0.002
		root.add_child(ring)
	return root


## Color of the target at a point on it, so the pieces keep the bullseye pattern.
func _bullseye_color(local_pos: Vector3) -> Color:
	var r := Vector2(local_pos.x, local_pos.y).length()
	if r > RING_RADII[0]:
		return WHITE
	if r > RING_RADII[1]:
		return RED
	if r > RING_RADII[2]:
		return WHITE
	return RED


func _build_environment() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.5, 0.0)
	_camera.fov = 60.0
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 1.2, SHELF_Z))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_room() -> void:
	_add_static_box(Vector3(0.0, -0.05, -5.0), Vector3(12.0, 0.1, 14.0), Color(0.35, 0.38, 0.42))  # floor
	_add_static_box(Vector3(0.0, 2.5, -9.0), Vector3(12.0, 5.0, 0.2), Color(0.55, 0.6, 0.68))  # back wall
	_add_static_box(Vector3(0.0, SHELF_TOP / 2.0, SHELF_Z), Vector3(SHELF_WIDTH, SHELF_TOP, 0.6), Color(0.45, 0.32, 0.22))  # shelf


func _add_static_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _material(color)
	mesh.mesh = box_mesh
	body.add_child(mesh)
	body.position = pos
	add_child(body)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui_layer = layer
	_score_label = Label.new()
	_score_label.position = Vector2(24.0, 16.0)
	_score_label.add_theme_font_size_override("font_size", 32)
	layer.add_child(_score_label)
	var hint := Label.new()
	hint.text = "Tap or click to throw"
	hint.position = Vector2(24.0, 60.0)
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color(1.0, 1.0, 1.0, 0.7)
	layer.add_child(hint)
	_update_score()


## A "+1" that floats up from where the target was hit.
func _show_score_pop(world_point: Vector3) -> void:
	if _camera.is_position_behind(world_point):
		return
	var pop := Label.new()
	pop.text = "+1"
	pop.add_theme_font_size_override("font_size", 40)
	pop.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	pop.position = _camera.unproject_position(world_point) - Vector2(20.0, 40.0)
	_ui_layer.add_child(pop)
	var tween := pop.create_tween().set_parallel(true)
	tween.tween_property(pop, "position:y", pop.position.y - 60.0, 0.7)
	tween.tween_property(pop, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(pop.queue_free)


func _update_score() -> void:
	_score_label.text = "Hits: %d   Throws: %d" % [_score, _throws]


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
