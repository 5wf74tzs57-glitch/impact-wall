extends Node3D
## Target Practice on an outdoor range: 10 throws a round.
##
## Targets keep appearing: pop-ups that rise out of the ground for 5 seconds,
## movers that slide along a rail at the back, and targets that peek out from
## behind hay bales. Some are friendlies (a smiley face): hitting one costs
## points. Scoring: bullseye 3, middle ring 2, outer ring 1, +1 bonus on a
## moving target, friendly -3, miss 0 (the score never goes below 0).
## There's no round clock: players walk up to collect the ball between throws,
## and new targets keep coming meanwhile.
## The scene is built in code so it is easy to read and change.

const GAME_ID := "target_practice"
const THROWS_PER_ROUND := 10
## Ring edges, outside in (meters from the center); match bullseye.gdshader.
const RING_RADII := [0.27, 0.18, 0.09]
const MOVER_BONUS := 1
const FRIENDLY_PENALTY := -3
## A ball that touches the ground, a hay bale or the berm counts as a miss
## after this long, unless it breaks a target first (a bounce can still hit).
const MISS_GRACE := 0.4

# Range layout (meters). The camera stands at z = 0 looking down the range.
# Distances and the camera's zoom are set so boards are big enough to hit on a
# projected wall: about 1/6 of the screen height up front, 1/10 at the back.
const POP_UP_Z := -5.0
const POP_UP_XS := [-2.9, -1.05, 1.45, 2.9]  # In the gaps between hay bales.
const PEEK_Z := -6.5
const COVER_XS := [-2.4, 0.3, 2.6]
const COVER_SIZE := Vector3(1.05, 0.95, 0.6)
const MOVER_Z := -8.5
const BERM_Z := -11.0

# How busy the range is.
const MAX_TARGETS := 3
const SPAWN_GAP := Vector2(0.9, 2.2)  # Seconds between new targets (min, max).
const FRIENDLY_CHANCE := 0.25

const TARGET_MODEL_PATH := "res://assets/targets/target_shards.glb"
const BULLSEYE_SHADER_PATH := "res://games/target_practice/bullseye.gdshader"
const FRIENDLY_SHADER_PATH := "res://games/target_practice/friendly.gdshader"

## Set false to stop targets appearing on their own (used by tests).
var auto_spawn := true

var _camera: Camera3D
var _bridge: ImpactBridge
var _round: RoundController
var _hud: GameHud
var _hub: UdpHitSource
var _target_model: PackedScene
var _bullseye: ShaderMaterial
var _friendly: ShaderMaterial
var _targets: Array[RangeTarget] = []
var _spawn_timer := 0.5
var _friendlies_hit := 0
var _balls_launched := 0
## Balls thrown this round that haven't been scored yet (instance ids).
var _pending_balls: Array[int] = []
## Each thrown ball's straight-line path: id -> [start, direction].
var _ball_paths := {}


func _ready() -> void:
	_target_model = load(TARGET_MODEL_PATH)
	if _target_model == null:
		push_error("Target model isn't imported yet. In Godot: Project > Reload Current Project.")
	_bullseye = _shader_material(BULLSEYE_SHADER_PATH)
	_friendly = _shader_material(FRIENDLY_SHADER_PATH)
	_build_environment()
	_build_range()

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

	_show_start_screen()


func _process(delta: float) -> void:
	if not auto_spawn or _target_model == null:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _targets.size() < MAX_TARGETS:
		_spawn_random_target()
		_spawn_timer = randf_range(SPAWN_GAP.x, SPAWN_GAP.y)


# --- Round flow -------------------------------------------------------------

func _show_start_screen() -> void:
	_hud.set_status("")
	var best := "\nBest: %d" % _round.best if _round.best > 0 else ""
	_hud.show_panel("Target Range",
		"Throw to start\n%d throws  ·  bullseye 3  ·  rings 2 and 1  ·  moving +1\nDon't hit the smiley friendlies: -3%s\n\n%s"
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
	_friendlies_hit = 0
	_pending_balls.clear()
	_ball_paths.clear()
	_hud.hide_panel()
	_update_status()
	_bridge.enabled = true


func _on_throw_recorded(_points: int, _throws_left: int) -> void:
	_update_status()


func _on_round_finished(score: int, best: int, is_new_best: bool) -> void:
	_bridge.enabled = false
	_hud.set_status("")
	var best_line := "New best!" if is_new_best else "Best: %d" % best
	var friendly_line := ""
	if _friendlies_hit > 0:
		friendly_line = "\nFriendlies hit: %d" % _friendlies_hit
	_hud.show_panel("Score %d" % score,
		"%d of %d hits%s\n%s\n\nThrow to play again" % [_round.hits, THROWS_PER_ROUND, friendly_line, best_line])


func _update_status() -> void:
	var shown := mini(_round.throws + 1, THROWS_PER_ROUND)
	_hud.set_status("Throw %d / %d      Score %d" % [shown, THROWS_PER_ROUND, _round.score])


# --- Targets ----------------------------------------------------------------

func _spawn_random_target() -> void:
	var roll := randf()
	var kind: RangeTarget.Kind
	if roll < 0.45:
		kind = RangeTarget.Kind.POP_UP
	elif roll < 0.75:
		kind = RangeTarget.Kind.PEEK
	else:
		kind = RangeTarget.Kind.MOVER
	var slot := _free_slot(kind)
	if slot == INF:
		return  # That lane is full; try again on the next spawn.
	spawn_target(kind, randf() < FRIENDLY_CHANCE, slot)


## Create one target. `x` is its lane position (a pop-up slot, a cover, or
## ignored for movers). Returns it, so tests can aim at it.
func spawn_target(kind: RangeTarget.Kind, friendly: bool, x: float = 0.0) -> RangeTarget:
	var t := RangeTarget.new()
	t.kind = kind
	t.friendly = friendly
	t.model = _target_model
	t.face_material = _friendly if friendly else _bullseye
	match kind:
		RangeTarget.Kind.POP_UP:
			t.position = Vector3(x, 0.0, POP_UP_Z)
			t.up_time = 5.0
		RangeTarget.Kind.PEEK:
			t.position = Vector3(x, 0.0, PEEK_Z)
			t.board_height = 0.5  # Low enough to hide fully behind the bale.
			# Side bales peek outward (clear of the pop-ups); the middle one either way.
			t.peek_side = signf(x) if absf(x) > 1.0 else (1.0 if randf() < 0.5 else -1.0)
		RangeTarget.Kind.MOVER:
			t.position = Vector3(0.0, 0.0, MOVER_Z)
			t.board_height = 1.85  # On a tall post, so it slides above everything else.
			t.up_time = 7.0
	t.shot.connect(_on_target_shot)
	t.finished.connect(_on_target_finished)
	add_child(t)
	_targets.append(t)
	return t


## A free spot in that target's lane, or INF if the lane is full.
func _free_slot(kind: RangeTarget.Kind) -> float:
	var used: Array[float] = []
	for t in _targets:
		if t.kind == kind:
			used.append(t.position.x)
	if kind == RangeTarget.Kind.MOVER:
		return 0.0 if used.is_empty() else INF
	var options: Array = (POP_UP_XS if kind == RangeTarget.Kind.POP_UP else COVER_XS).duplicate()
	options.shuffle()
	for x in options:
		if float(x) not in used:
			return float(x)
	return INF


func _on_target_finished(target: RangeTarget) -> void:
	_targets.erase(target)


func _on_target_shot(target: RangeTarget, local_hit: Vector3, world_hit: Vector3) -> void:
	var ball_id := _nearest_pending_ball(world_hit)
	if ball_id == 0:
		return  # Not from a thrown ball this round (e.g. on the results screen).
	_pending_balls.erase(ball_id)
	# Balls fly straight until their first contact, so the exact spot they hit
	# the board is where their path crosses its face. (The collision point the
	# physics engine reports is a little off once the ball starts to bounce.)
	if _ball_paths.has(ball_id) and is_instance_valid(target.body):
		local_hit = _path_hit_on_board(_ball_paths[ball_id], target.body)
	var points: int
	var text: String
	var color := Color(1.0, 0.85, 0.3)
	if target.friendly:
		points = FRIENDLY_PENALTY
		_friendlies_hit += 1
		text = "Friendly! %d" % points
		color = Color(1.0, 0.4, 0.35)
	else:
		points = _ring_points(local_hit)
		text = "+%d" % points
		if target.kind == RangeTarget.Kind.MOVER:
			points += MOVER_BONUS
			text = "+%d moving!" % points
	if not _camera.is_position_behind(world_hit):
		_hud.show_pop(text, _camera.unproject_position(world_hit), color)
	_round.record_throw(points)


## Where a straight path [start, direction] crosses a board's front face, in
## the board's own coordinates.
func _path_hit_on_board(path: Array, board: Node3D) -> Vector3:
	var start: Vector3 = path[0]
	var direction: Vector3 = path[1]
	var normal := board.global_transform.basis.z.normalized()
	var face_point := board.global_transform * Vector3(0.0, 0.0, RangeTarget.BOARD_SIZE.z / 2.0)
	var facing := direction.dot(normal)
	if absf(facing) < 0.001:
		return board.to_local(start)
	var distance := (face_point - start).dot(normal) / facing
	return board.to_local(start + direction * distance)


## Points for a hit at a spot on a board (meters from its center).
func _ring_points(local_pos: Vector3) -> int:
	var r := Vector2(local_pos.x, local_pos.y).length()
	if r <= RING_RADII[2]:
		return 3
	if r <= RING_RADII[1]:
		return 2
	return 1


# --- Throws -----------------------------------------------------------------

func _on_ball_launched(ball: RigidBody3D, _event: HitEvent) -> void:
	_balls_launched += 1
	_pending_balls.append(ball.get_instance_id())
	_ball_paths[ball.get_instance_id()] = [ball.global_position, ball.linear_velocity.normalized()]
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


# --- Building the range -----------------------------------------------------

func _build_environment() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.6, 0.0)
	_camera.fov = 40.0
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.9, -6.5))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.95)
	sky_mat.ground_horizon_color = Color(0.6, 0.66, 0.55)
	sky_mat.ground_bottom_color = Color(0.3, 0.36, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_range() -> void:
	var grass := Color(0.22, 0.42, 0.16)
	_add_box(Vector3(0.0, -0.05, -20.0), Vector3(80.0, 0.1, 60.0), grass, true)  # ground
	# Earth berm behind the range: catches stray balls.
	_add_box(Vector3(0.0, 1.2, BERM_Z), Vector3(30.0, 2.4, 2.0), Color(0.42, 0.33, 0.2), true)
	_add_box(Vector3(0.0, 2.45, BERM_Z), Vector3(30.0, 0.1, 2.0), Color(0.2, 0.38, 0.15), false)
	# Hay bales the peek targets hide behind (in front of the targets).
	for x in COVER_XS:
		_add_box(Vector3(float(x), COVER_SIZE.y / 2.0, PEEK_Z + 0.6), COVER_SIZE, Color(0.78, 0.6, 0.25), true)
		_add_box(Vector3(float(x), COVER_SIZE.y / 2.0, PEEK_Z + 0.6), COVER_SIZE * Vector3(1.02, 0.15, 1.02), Color(0.55, 0.4, 0.15), false)
	# The rail the movers slide along, and the lane markers on the ground.
	_add_box(Vector3(0.0, 0.08, MOVER_Z), Vector3(8.2, 0.16, 0.2), Color(0.3, 0.3, 0.33), false)  # mover rail
	for z in [POP_UP_Z, PEEK_Z, MOVER_Z]:
		_add_box(Vector3(0.0, 0.005, float(z) + 0.5), Vector3(9.0, 0.01, 0.08), Color(0.9, 0.9, 0.85), false)
	# A few trees for scenery (no collision, so they never block a throw).
	for spot in [Vector3(-6.0, 0, -9.5), Vector3(-4.5, 0, -13), Vector3(6.0, 0, -10), Vector3(7.5, 0, -13.5), Vector3(-7.5, 0, -6.5), Vector3(7.5, 0, -6)]:
		_add_tree(spot)


func _add_box(pos: Vector3, size: Vector3, color: Color, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _material(color)
	mesh.mesh = box_mesh
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		body.add_child(mesh)
		body.position = pos
		add_child(body)
	else:
		mesh.position = pos
		add_child(mesh)


func _add_tree(base: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.2
	trunk_mesh.height = 2.0
	trunk_mesh.material = _material(Color(0.4, 0.28, 0.18))
	trunk.mesh = trunk_mesh
	trunk.position = base + Vector3(0.0, 1.0, 0.0)
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.3
	crown_mesh.height = 2.4
	crown_mesh.material = _material(Color(0.15, 0.33, 0.13))
	crown.mesh = crown_mesh
	crown.position = base + Vector3(0.0, 2.8, 0.0)
	add_child(crown)


func _shader_material(path: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	return mat


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat
