extends Node3D
## Target Practice on an outdoor range: 10 throws a round.
##
## Person-shaped targets keep appearing at four depths: pop-ups that rise out
## of the ground for 5 seconds, movers that slide along a rail, movers that walk
## toward or away from you, and targets that peek out from behind hay bales.
## Blue ones with a smiley face are friendlies: hitting one costs points.
##
## Scoring: bullseye 5, rings 3 and 2, anywhere else on the target 1; +1 on a
## moving target; then x2 for mid-range and x3 for far targets. Friendly -5,
## miss 0 (the score never goes below 0).
## There's no round clock: players walk up to collect the ball between throws,
## and new targets keep coming meanwhile.
## The scene is built in code so it is easy to read and change.

const GAME_ID := "target_practice"
const THROWS_PER_ROUND := 10
## Points for the bullseye and each ring around it, then the rest of the target.
const ZONE_POINTS := [5, 3, 2]
const BODY_POINTS := 1
const MOVING_BONUS := 1
const FRIENDLY_PENALTY := -5
## Distance multipliers: hits closer than the first distance x1, closer than
## the second x2, anything farther x3 (meters from the camera).
const MULTIPLIER_DISTANCES := [8.0, 12.5]
## A ball that touches the ground or a hay bale counts as a miss after this
## long, unless it breaks a target first (a bounce can still hit).
const MISS_GRACE := 0.4
## A ball that flies past everything counts as a miss once it's this far out.
const MISS_Z := -24.0

# Range layout (meters). The camera stands at z = 0 looking down the range.
# The near targets are about 1/6 of the screen height; far ones about 1/16.
const NEAR_Z := -5.0
const NEAR_XS := [-2.6, -0.9, 0.9, 2.6]
const PEEK_Z := -8.0
const COVER_XS := [-3.0, 0.0, 3.0]
const COVER_SIZE := Vector3(1.0, 1.15, 0.6)
const MID_Z := -11.0
const MID_XS := [-4.0, -2.0, 0.0, 2.0, 4.0]
## Board heights by row: farther rows stand on taller posts so they show above
## the hay bales in front.
const NEAR_HEIGHT := 0.85
const MID_HEIGHT := 1.4
const FAR_HEIGHT := 1.5
const MOVER_Z := -20.0  # Far back and up high: its own band on screen.
const FAR_Z := -16.0
const FAR_XS := [-6.0, -3.0, 0.0, 3.0, 6.0]
const DEPTH_XS := [-4.6, 4.6]  # Outside the hay bales.
const DEPTH_RANGE := Vector2(-9.0, -17.0)  # Walkers go between these distances.

# How busy the range is.
const MAX_TARGETS := 4
const SPAWN_GAP := Vector2(0.8, 2.0)  # Seconds between new targets (min, max).
const FRIENDLY_CHANCE := 0.25

const TARGET_MODEL_PATH := "res://assets/targets/person_target.glb"
const TARGET_SHADER_PATH := "res://games/target_practice/person_target.gdshader"
const FRIENDLY_SHADER_PATH := "res://games/target_practice/friendly.gdshader"

## Set false to stop targets appearing on their own (used by tests).
var auto_spawn := true

var _camera: Camera3D
var _bridge: ImpactBridge
var _round: RoundController
var _hud: GameHud
var _hub: UdpHitSource
var _target_model: PackedScene
var _target_face: ShaderMaterial
var _friendly_face: ShaderMaterial
var _targets: Array[RangeTarget] = []
## The screen area each live target covers over its whole life.
var _footprints := {}
## The screen area each hay bale covers (only peek targets may hide there).
var _cover_areas: Array[Rect2] = []
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
	_target_face = _shader_material(TARGET_SHADER_PATH)
	_friendly_face = _shader_material(FRIENDLY_SHADER_PATH)
	_build_environment()
	_build_range()
	_measure_cover()

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


func _physics_process(_delta: float) -> void:
	# Balls that sail off into the trees never touch anything: call them misses.
	for id in _pending_balls.duplicate():
		var ball := instance_from_id(id) as Node3D
		if ball != null and (ball.global_position.z < MISS_Z or ball.global_position.y < -0.5):
			_score_miss(id)


# --- Round flow -------------------------------------------------------------

func _show_start_screen() -> void:
	_hud.set_status("")
	var best := "\nBest: %d" % _round.best if _round.best > 0 else ""
	_hud.show_panel("Target Range",
		("Throw to start  ·  %d throws\nBullseye 5 · rings 3 and 2 · moving +1 · far targets x2 and x3\n"
		+ "Don't hit the blue smiley friendlies: %d%s\n\n%s")
		% [THROWS_PER_ROUND, FRIENDLY_PENALTY, best, _hub_status()])


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
	# Try a few random targets and keep the first that doesn't overlap any
	# target already on the range, anywhere along its path.
	for attempt in 6:
		var t := _random_target()
		var area := t.screen_footprint(_camera)
		var behind_cover := t.kind != RangeTarget.Kind.PEEK and _overlaps_cover(area)
		if not behind_cover and not _overlaps_live_target(area):
			_add_target(t, area)
			return
		t.free()


func _random_target() -> RangeTarget:
	var friendly := randf() < FRIENDLY_CHANCE
	var roll := randf()
	if roll < 0.24:
		return make_target(RangeTarget.Kind.POP_UP, friendly, _pick(NEAR_XS), NEAR_Z)
	if roll < 0.44:
		return make_target(RangeTarget.Kind.POP_UP, friendly, _pick(MID_XS), MID_Z)
	if roll < 0.58:
		return make_target(RangeTarget.Kind.POP_UP, friendly, _pick(FAR_XS), FAR_Z)
	if roll < 0.74:
		return make_target(RangeTarget.Kind.PEEK, friendly, _pick(COVER_XS))
	if roll < 0.87:
		return make_target(RangeTarget.Kind.MOVER, friendly)
	return make_target(RangeTarget.Kind.DEPTH, friendly, _pick(DEPTH_XS))


## Make a target, set up for its lane, without putting it on the range yet.
## `x` is its spot in the lane; `z` is only used by pop-ups (which row).
func make_target(kind: RangeTarget.Kind, friendly: bool, x: float = 0.0, z: float = NEAR_Z) -> RangeTarget:
	var t := RangeTarget.new()
	t.kind = kind
	t.friendly = friendly
	t.model = _target_model
	t.face_material = _friendly_face if friendly else _target_face
	match kind:
		RangeTarget.Kind.POP_UP:
			t.position = Vector3(x, 0.0, z)
			t.up_time = 5.0
			t.board_height = FAR_HEIGHT if z <= FAR_Z else (MID_HEIGHT if z <= MID_Z else NEAR_HEIGHT)
		RangeTarget.Kind.PEEK:
			t.position = Vector3(x, 0.0, PEEK_Z)
			t.board_height = 0.55  # Low enough to hide fully behind the bale.
			# Side bales peek outward; the middle one either way.
			t.peek_side = signf(x) if absf(x) > 1.0 else (1.0 if randf() < 0.5 else -1.0)
		RangeTarget.Kind.MOVER:
			t.position = Vector3(0.0, 0.0, MOVER_Z)
			t.board_height = 2.5  # On a tall post, so it slides above the others.
			t.rail_half_width = 4.5
			t.up_time = 7.0
		RangeTarget.Kind.DEPTH:
			t.position = Vector3(x, 0.0, 0.0)
			t.board_height = 1.75  # Tall post: stays above the hay bales on screen.
			t.move_speed = 1.6
			# Half walk away from you, half walk toward you.
			if randf() < 0.5:
				t.depth_from = DEPTH_RANGE.x
				t.depth_to = DEPTH_RANGE.y
			else:
				t.depth_from = DEPTH_RANGE.y
				t.depth_to = DEPTH_RANGE.x
	return t


## Make a target and put it on the range now (tests use this to aim).
func spawn_target(kind: RangeTarget.Kind, friendly: bool, x: float = 0.0, z: float = NEAR_Z) -> RangeTarget:
	var t := make_target(kind, friendly, x, z)
	_add_target(t, t.screen_footprint(_camera))
	return t


func _add_target(t: RangeTarget, area: Rect2) -> void:
	t.shot.connect(_on_target_shot)
	t.finished.connect(_on_target_finished)
	add_child(t)
	_targets.append(t)
	_footprints[t] = area


func _overlaps_cover(area: Rect2) -> bool:
	for cover in _cover_areas:
		if area.intersects(cover):
			return true
	return false


## Work out where each hay bale is on screen (its front face and top).
func _measure_cover() -> void:
	for x in COVER_XS:
		var rect := Rect2()
		var first := true
		for dx in [-0.5, 0.5]:
			for y in [0.0, COVER_SIZE.y]:
				for dz in [0.0, COVER_SIZE.z]:
					var corner := Vector3(float(x) + dx * COVER_SIZE.x, y, PEEK_Z + 0.6 + COVER_SIZE.z / 2.0 - dz)
					var p := _camera.unproject_position(corner)
					rect = Rect2(p, Vector2.ZERO) if first else rect.expand(p)
					first = false
		_cover_areas.append(rect)


func _overlaps_live_target(area: Rect2) -> bool:
	for t in _targets:
		if area.intersects(_footprints[t]):
			return true
	return false


func _pick(options: Array) -> float:
	return float(options[randi() % options.size()])


func _on_target_finished(target: RangeTarget) -> void:
	_targets.erase(target)
	_footprints.erase(target)


func _on_target_shot(target: RangeTarget, local_hit: Vector3, world_hit: Vector3) -> void:
	# The board is gone, so its spot is free for a new target.
	_footprints[target] = Rect2()
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
		var base := _zone_points(Vector2(local_hit.x, local_hit.y))
		var moving := target.kind == RangeTarget.Kind.MOVER or target.kind == RangeTarget.Kind.DEPTH
		if moving:
			base += MOVING_BONUS
		var multiplier := distance_multiplier(world_hit)
		points = base * multiplier
		text = "+%d" % points
		if multiplier > 1:
			text += "  (x%d far)" % multiplier
		if moving:
			text += "  moving!"
	if not _camera.is_position_behind(world_hit):
		_hud.show_pop(text, _camera.unproject_position(world_hit), color)
	_round.record_throw(points)


## Where a straight path [start, direction] crosses a board's front face, in
## the board's own coordinates.
func _path_hit_on_board(path: Array, board: Node3D) -> Vector3:
	var start: Vector3 = path[0]
	var direction: Vector3 = path[1]
	var normal := board.global_transform.basis.z.normalized()
	var face_point := board.global_transform * Vector3(0.0, 0.0, RangeTarget.THICKNESS / 2.0)
	var facing := direction.dot(normal)
	if absf(facing) < 0.001:
		return board.to_local(start)
	var distance := (face_point - start).dot(normal) / facing
	return board.to_local(start + direction * distance)


## Points for where the ball struck the silhouette (meters from its center).
func _zone_points(local: Vector2) -> int:
	if not RangeTarget.is_on_board(local):
		return BODY_POINTS  # Clipped an edge.
	var r := local.distance_to(RangeTarget.BULL_CENTER)
	for i in RangeTarget.BULL_RINGS.size():
		if r <= RangeTarget.BULL_RINGS[i]:
			return ZONE_POINTS[i]
	return BODY_POINTS


## x1 near, x2 mid-range, x3 far: how far the hit was from the camera.
func distance_multiplier(world_point: Vector3) -> int:
	var d := Vector2(world_point.x, world_point.z).distance_to(Vector2(_camera.global_position.x, _camera.global_position.z))
	if d < MULTIPLIER_DISTANCES[0]:
		return 1
	if d < MULTIPLIER_DISTANCES[1]:
		return 2
	return 3


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
		var at := _camera.unproject_position(ball.global_position)
		var screen := get_viewport().get_visible_rect().size
		at = at.clamp(Vector2(80, 80), screen - Vector2(80, 80))  # Keep it on screen.
		_hud.show_pop("Miss", at, Color(0.85, 0.88, 0.95))
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
	_camera.far = 150.0
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.9, -9.0))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var horizon := Color(0.72, 0.84, 0.95)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.85)
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = Color(0.6, 0.66, 0.55)
	sky_mat.ground_bottom_color = Color(0.3, 0.36, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	# Light haze, so the trees fade into the distance.
	env.fog_enabled = true
	env.fog_light_color = horizon
	env.fog_density = 0.008
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_range() -> void:
	_add_box(Vector3(0.0, -0.05, -70.0), Vector3(240.0, 0.1, 160.0), Color(0.22, 0.42, 0.16), true)  # ground
	# Hay bales the peek targets hide behind (in front of the targets).
	for x in COVER_XS:
		var spot := Vector3(float(x), COVER_SIZE.y / 2.0, PEEK_Z + 0.6)
		_add_box(spot, COVER_SIZE, Color(0.78, 0.6, 0.25), true)
		_add_box(spot, COVER_SIZE * Vector3(1.02, 0.12, 1.02), Color(0.55, 0.4, 0.15), false)
	# The rail the side-to-side movers run on, and a line marking each row.
	_add_box(Vector3(0.0, 0.08, MOVER_Z), Vector3(10.0, 0.16, 0.2), Color(0.3, 0.3, 0.33), false)
	for z in [NEAR_Z, PEEK_Z, MID_Z, FAR_Z]:
		_add_box(Vector3(0.0, 0.005, float(z) + 0.5), Vector3(14.0, 0.01, 0.08), Color(0.9, 0.9, 0.85), false)
	_add_forest()


## Trees down both sides of the range and filling the distance. Drawn as two
## MultiMeshes (trunks and tops), which is cheap for phones. No collision, so
## they never block a throw.
func _add_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2027  # Same forest every time.
	var spots: Array[Transform3D] = []
	for i in 170:
		var z := rng.randf_range(-6.0, -110.0)
		var x: float
		if z > -24.0:
			# Leave the shooting lanes clear: trees only at the sides up close.
			x = rng.randf_range(7.0, 30.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		else:
			x = rng.randf_range(-70.0, 70.0)
		var s := rng.randf_range(0.8, 1.9)
		spots.append(Transform3D(Basis().scaled(Vector3(s, s, s)).rotated(Vector3.UP, rng.randf() * TAU), Vector3(x, 0.0, z)))

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 2.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.material = _material(Color(0.4, 0.28, 0.18))
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.3
	crown_mesh.height = 2.6
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 6
	crown_mesh.material = _material(Color(0.15, 0.33, 0.13))
	_add_multimesh(trunk_mesh, spots, Vector3(0.0, 1.0, 0.0))
	_add_multimesh(crown_mesh, spots, Vector3(0.0, 2.9, 0.0))


func _add_multimesh(mesh: Mesh, spots: Array[Transform3D], offset: Vector3) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var t := spots[i]
		mm.set_instance_transform(i, Transform3D(t.basis, t.origin + t.basis * offset))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	add_child(node)


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


func _shader_material(path: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	return mat


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat
