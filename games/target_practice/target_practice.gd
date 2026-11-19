extends Node3D
## Target Practice: throw at the bullseye, 10 throws a round.
##
## Any hit starts a round. Each throw scores by where it lands: bullseye 3,
## middle ring 2, outer ring or board edge 1, miss 0. The target shatters on a
## hit and a new one appears somewhere else on the shelf. After 10 throws the
## results screen shows the score and the best score; any hit plays again.
## There is no clock: players walk up to collect the ball between throws.
## The scene is built in code so it is easy to read and change.

const GAME_ID := "target_practice"
const THROWS_PER_ROUND := 10
const SHELF_Z := -6.0
const SHELF_TOP := 1.0
const SHELF_WIDTH := 4.0
const TARGET_SIZE := Vector3(0.6, 0.6, 0.15)
const RESPAWN_DELAY := 1.2
## Ring edges, outside in (meters from the center); match bullseye.gdshader.
const RING_RADII := [0.27, 0.18, 0.09]
## A ball that touches a wall, floor or shelf counts as a miss after this
## long, unless it breaks a target first (a bounce can still hit).
const MISS_GRACE := 0.4
## The target board and its pre-broken shards, made in Blender by
## tools/blender/make_target_shards.py.
const TARGET_MODEL_PATH := "res://assets/targets/target_shards.glb"
const BULLSEYE_SHADER_PATH := "res://games/target_practice/bullseye.gdshader"

var _camera: Camera3D
var _bridge: ImpactBridge
var _round: RoundController
var _hud: GameHud
var _hub: UdpHitSource
var _target: RigidBody3D
var _target_knocked := false
var _target_model: PackedScene
var _bullseye: ShaderMaterial
var _balls_launched := 0
## Balls thrown this round that haven't been scored yet (instance ids).
var _pending_balls: Array[int] = []


func _ready() -> void:
	_target_model = load(TARGET_MODEL_PATH)
	if _target_model == null:
		push_warning("Target model isn't imported yet, so using a plain target. "
			+ "In Godot: Project > Reload Current Project.")
	_bullseye = ShaderMaterial.new()
	_bullseye.shader = load(BULLSEYE_SHADER_PATH)
	_build_environment()
	_build_room()

	_hud = GameHud.new()
	add_child(_hud)

	add_child(TapHitSource.new())  # Taps and clicks always work too.
	_hub = UdpHitSource.new()  # The real hub, over Wi-Fi (docs/hub_protocol.md).
	add_child(_hub)
	_hub.hub_connected.connect(_on_hub_connected)
	var hub_info := HubOverlay.new()  # Press H to see what the hub is sending.
	hub_info.source = _hub
	add_child(hub_info)

	_bridge = ImpactBridge.new()
	_bridge.camera = _camera
	_bridge.enabled = false  # Until a round starts.
	add_child(_bridge)
	_bridge.ball_launched.connect(_on_ball_launched)

	_round = RoundController.new()
	_round.game_id = GAME_ID
	_round.throws_per_round = THROWS_PER_ROUND
	add_child(_round)
	_round.round_started.connect(_on_round_started)
	_round.throw_recorded.connect(_on_throw_recorded)
	_round.round_finished.connect(_on_round_finished)

	_spawn_target()
	_show_start_screen()


func _physics_process(_delta: float) -> void:
	# Backup: a soft hit can knock the target over without shattering it.
	if not is_instance_valid(_target) or _target_knocked:
		return
	var fell := _target.global_position.y < SHELF_TOP - 0.2
	var tipped := _target.global_transform.basis.y.dot(Vector3.UP) < 0.5
	if fell or tipped:
		_on_target_hit(_target.global_position, 1)


# --- Round flow -------------------------------------------------------------

func _show_start_screen() -> void:
	_hud.set_status("")
	var best := "\nBest: %d" % _round.best if _round.best > 0 else ""
	_hud.show_panel("Target Practice",
		"Throw to start\n%d throws  ·  bullseye 3  ·  rings 2 and 1%s\n\n%s"
		% [THROWS_PER_ROUND, best, _hub_status()])


func _hub_status() -> String:
	if _hub.connected:
		return "Hub connected (%s)" % _hub.hub_name
	return "No hub found: tap or click to play  ·  H = hub info"


func _on_hub_connected(_hub_name: String) -> void:
	if _round.state == RoundController.State.READY:
		_show_start_screen()  # Refresh the hub line.


func _on_round_started() -> void:
	_balls_launched = 0
	_pending_balls.clear()
	_hud.hide_panel()
	_update_status()
	if not is_instance_valid(_target) or _target_knocked:
		_spawn_target()
	_bridge.enabled = true


func _on_throw_recorded(_points: int, _throws_left: int) -> void:
	_update_status()


func _on_round_finished(score: int, best: int, is_new_best: bool) -> void:
	_bridge.enabled = false
	_hud.set_status("")
	var best_line := "New best!" if is_new_best else "Best: %d" % best
	_hud.show_panel("Score %d" % score,
		"%d of %d hits\n%s\n\nThrow to play again" % [_round.hits, THROWS_PER_ROUND, best_line])


func _update_status() -> void:
	var shown := mini(_round.throws + 1, THROWS_PER_ROUND)
	_hud.set_status("Throw %d / %d      Score %d" % [shown, THROWS_PER_ROUND, _round.score])


# --- Throws -----------------------------------------------------------------

func _on_ball_launched(ball: RigidBody3D, _event: HitEvent) -> void:
	_balls_launched += 1
	_pending_balls.append(ball.get_instance_id())
	ball.body_entered.connect(_on_ball_contact.bind(ball.get_instance_id()))
	ball.tree_exiting.connect(_on_ball_gone.bind(ball.get_instance_id()))
	if _balls_launched >= THROWS_PER_ROUND:
		_bridge.enabled = false  # Last throw of the round is in the air.


func _on_ball_contact(body: Node, ball_id: int) -> void:
	if body is StaticBody3D and ball_id in _pending_balls:
		get_tree().create_timer(MISS_GRACE).timeout.connect(_score_miss.bind(ball_id))


func _on_ball_gone(ball_id: int) -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		_score_miss(ball_id)


func _score_miss(ball_id: int) -> void:
	if ball_id not in _pending_balls:
		return  # Already scored (it hit something).
	_pending_balls.erase(ball_id)
	var ball := instance_from_id(ball_id) as Node3D
	if ball != null and not _camera.is_position_behind(ball.global_position):
		_hud.show_pop("Miss", _camera.unproject_position(ball.global_position), Color(0.85, 0.88, 0.95))
	_round.record_throw(0)


func _on_target_broken(hit_point: Vector3) -> void:
	# The target still exists at this moment; it's removed right after.
	_on_target_hit(hit_point, _ring_points(_target.to_local(hit_point)))
	_target = null


func _on_target_hit(world_point: Vector3, points: int) -> void:
	if _target_knocked:
		return
	_target_knocked = true
	var ball_id := _nearest_pending_ball(world_point)
	if ball_id != 0:
		_pending_balls.erase(ball_id)
		if not _camera.is_position_behind(world_point):
			_hud.show_pop("+%d" % points, _camera.unproject_position(world_point))
		_round.record_throw(points)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_spawn_target)


## Points for a hit at a spot on the target's face (target-local position).
func _ring_points(local_pos: Vector3) -> int:
	var r := Vector2(local_pos.x, local_pos.y).length()
	if r <= RING_RADII[2]:
		return 3
	if r <= RING_RADII[1]:
		return 2
	return 1


func _nearest_pending_ball(world_point: Vector3) -> int:
	var best_id := 0
	var best_dist := INF
	for id in _pending_balls:
		var ball := instance_from_id(id) as Node3D
		if ball == null:
			continue
		var d := ball.global_position.distance_to(world_point)
		if d < best_dist:
			best_dist = d
			best_id = id
	return best_id


# --- Building the scene -----------------------------------------------------

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
	_target.add_child(_make_target_visual())
	var breakable := Breakable.new()
	if _target_model != null:
		breakable.pieces_scene = _target_model
		var face_materials: Array[Material] = [_bullseye]  # surface 0 = outside; 1 = broken edges
		breakable.surface_materials = face_materials
	else:
		breakable.size = TARGET_SIZE  # Plain box pieces until the model is imported.
	breakable.broken.connect(_on_target_broken)
	_target.add_child(breakable)
	add_child(_target)
	var x := randf_range(-SHELF_WIDTH / 2.0 + 0.5, SHELF_WIDTH / 2.0 - 0.5)
	_target.global_position = Vector3(x, SHELF_TOP + TARGET_SIZE.y / 2.0, SHELF_Z)
	_target_knocked = false


## The intact board from the Blender model, with the bullseye on it.
func _make_target_visual() -> Node3D:
	if _target_model == null:
		return _make_plain_target()
	var model := _target_model.instantiate() as Node3D
	var shards := model.find_child("Shards", true, false)
	if shards != null:
		shards.free()  # The pieces are only used when it breaks.
	var board := model.find_child("Intact", true, false) as MeshInstance3D
	if board != null:
		board.set_surface_override_material(0, _bullseye)
	return model


## A simple stand-in board, used only if the Blender model hasn't been imported.
func _make_plain_target() -> Node3D:
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = TARGET_SIZE
	box.material = _material(Color(0.95, 0.95, 0.92))
	board.mesh = box
	var dot := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.15
	disc.bottom_radius = 0.15
	disc.height = 0.01
	disc.material = _material(Color(0.9, 0.2, 0.18))
	dot.mesh = disc
	dot.rotation_degrees.x = 90.0
	dot.position.z = TARGET_SIZE.z / 2.0 + 0.006
	board.add_child(dot)
	return board


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


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
