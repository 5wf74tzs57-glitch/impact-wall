extends SceneTree
## Alignment test for the cartoon target:
##  1. The hit area matches the drawn silhouette: a grid of rays is fired at
##     a target and each is checked against the physics hit area and against
##     the visible part meshes. They must agree almost everywhere (a sliver
##     along the edges is allowed for the physics engine's rounding).
##  2. Throws at each printed ring score that ring's number and break the
##     right part (head -> just the head, outer side -> that side, inner
##     rings -> everything).
##
##   godot --headless --path . -s res://tests/target_alignment_test.gd

const SCENE := "res://games/target_practice/target_practice.tscn"
const SLOTS := [-2.6, -0.9, 0.9, 2.6]

var game: Node3D
var camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)  # The real 16:9 screen shape (headless defaults to square).
	game = (load(SCENE) as PackedScene).instantiate()
	game.set("auto_spawn", false)
	root.add_child(game)
	await _frames(10)
	camera = game.get("_camera")

	# --- 1. Hit area vs drawn shape -------------------------------------------
	var target: RangeTarget = game.spawn_target(RangeTarget.Kind.POP_UP, false, 0.0, -5.0)
	await _frames(45)
	var triangles := _visible_triangles(target)
	var space := target.get_world_3d().direct_space_state
	var rays := 0
	var mismatches := 0
	var worst := ""
	var x := -0.34
	while x <= 0.34:
		var y := -0.49
		while y <= 0.49:
			var from_l := Vector3(x, y, 0.5)
			var to_l := Vector3(x, y, -0.5)
			var query := PhysicsRayQueryParameters3D.create(target.body.to_global(from_l), target.body.to_global(to_l))
			var hit := space.intersect_ray(query)
			var physics_hit: bool = not hit.is_empty() and hit.collider == target.body
			var drawn_hit := _ray_hits(triangles, from_l, Vector3(0, 0, -1))
			if physics_hit != drawn_hit:
				mismatches += 1
				worst = "(%.2f, %.2f) physics=%s drawn=%s" % [x, y, physics_hit, drawn_hit]
			rays += 1
			y += 0.01
		x += 0.01
	var mismatch_pct := 100.0 * mismatches / rays
	print("hit area: %d rays, %d disagree (%.2f%%)%s" % [rays, mismatches, mismatch_pct, "; e.g. " + worst if worst != "" else ""])
	target.queue_free()
	await _frames(5)

	# --- 2. Points and which part breaks --------------------------------------
	var round: RoundController = game.get("_round")
	round.reset_best()
	_hit(Vector2.ZERO)  # Start the round.
	await _frames(5)
	var bull := RangeTarget.BULL_CENTER
	var head := RangeTarget.HEAD_CENTER
	var d := Vector2(cos(PI / 4.0), sin(PI / 4.0))
	var cases := [
		["chest 5 (center)", bull, 5, []],
		["chest 4", bull + d * 0.08, 4, []],
		["chest 3", bull + d * 0.134, 3, []],
		["chest 2", bull + d * 0.186, 2, []],
		["chest 1, right side", bull + Vector2(0.237, 0.0), 1, ["Right"]],
		["body corner, left side", Vector2(-0.27, -0.42), 1, ["Left"]],
		["head 5", head, 5, ["Head"]],
		["head 4", head + Vector2(0.05, 0.0), 4, ["Head"]],
		["head 3", head + Vector2(0.0, 0.08), 3, ["Head"]],
		["head 2", head + Vector2(-0.12, 0.0), 2, ["Head"]],
	]
	var failures: Array[String] = []
	for i in cases.size():
		var c: Array = cases[i]
		var t: RangeTarget = game.spawn_target(RangeTarget.Kind.POP_UP, false, SLOTS[i % SLOTS.size()], -5.0)
		await _frames(45)
		var before := round.score
		var spot: Vector2 = c[1]
		_hit(camera.unproject_position(t.body.to_global(Vector3(spot.x, spot.y, RangeTarget.THICKNESS / 2.0))))
		await _frames(25)
		var got := round.score - before
		var broke := ""
		if not is_instance_valid(t) or not is_instance_valid(t.body):
			broke = "everything"
		else:
			var gone: Array[String] = []
			for p in RangeTarget.MODEL_PARTS:
				if not (p in t.breakable.remaining_parts()):
					gone.append(p)
			broke = "everything" if gone.size() == 4 else ", ".join(gone)
		var want_broke: String = "everything" if (c[3] as Array).is_empty() else ", ".join(c[3])
		var line := "%-24s points %d (want %d)  broke: %s (want %s)" % [c[0], got, c[2], broke, want_broke]
		print(line)
		if got != c[2] or broke != want_broke:
			failures.append(line)
		await _frames(50)

	var ok := mismatch_pct <= 1.0 and failures.is_empty()
	print(("PASS: " if ok else "FAIL: ") + "hit area mismatch %.2f%%, %d of %d throws wrong" % [mismatch_pct, failures.size(), cases.size()])
	round.reset_best()
	quit(0 if ok else 1)


## The visible part meshes as triangles, in the board body's coordinates.
func _visible_triangles(target: RangeTarget) -> PackedVector3Array:
	var tris := PackedVector3Array()
	for node in target.body.find_children("Part_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var to_body := target.body.global_transform.affine_inverse() * mi.global_transform
		var faces := mi.mesh.get_faces()
		for v in faces:
			tris.append(to_body * v)
	return tris


func _ray_hits(tris: PackedVector3Array, from: Vector3, dir: Vector3) -> bool:
	for i in range(0, tris.size(), 3):
		if Geometry3D.ray_intersects_triangle(from, dir, tris[i], tris[i + 1], tris[i + 2]) != null:
			return true
	return false


func _hit(point: Vector2) -> void:
	root.get_node("HitBus").emit_hit(HitEvent.create(point, 0.7, "test"))


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
