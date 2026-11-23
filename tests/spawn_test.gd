extends SceneTree
## Spawn test: let targets appear on their own (sped up) and check that no
## two live targets ever share screen space and none hides behind a hay bale
## (except peek targets, which are meant to). Then hit a target walking toward
## or away from the camera and check it scores with the moving bonus.
##
##   godot --headless --path . -s res://tests/spawn_test.gd

const SCENE := "res://games/target_practice/target_practice.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)  # The real 16:9 screen shape (headless defaults to square).
	var game: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(game)
	Engine.time_scale = 4.0  # 40 seconds of range time in about 10.
	var seen := {}
	var most_at_once := 0
	var problem := ""
	for i in 600:
		await physics_frame
		var targets: Array = game.get("_targets")
		var areas: Dictionary = game.get("_footprints")
		var covers: Array = game.get("_cover_areas")
		most_at_once = maxi(most_at_once, targets.size())
		for a in targets.size():
			var ta: RangeTarget = targets[a]
			seen[ta.kind] = true
			var ra: Rect2 = areas[ta]
			if ra.has_area() and ta.kind != RangeTarget.Kind.PEEK:
				for c in covers:
					if ra.intersects(c):
						problem = "a %s target spawned behind a hay bale" % RangeTarget.Kind.keys()[ta.kind]
			for b in range(a + 1, targets.size()):
				var rb: Rect2 = areas[targets[b]]
				if ra.has_area() and rb.has_area() and ra.intersects(rb):
					problem = "two targets overlap on screen"
	Engine.time_scale = 1.0
	if problem != "":
		_finish(false, problem)
		return
	if seen.size() < 4 or most_at_once < 2:
		_finish(false, "expected all 4 kinds and several at once; kinds=%s most=%d" % [seen.keys(), most_at_once])
		return

	# Hit a walker (toward or away from the camera): it scores, with the moving bonus.
	game.set("auto_spawn", false)
	for t in game.get("_targets").duplicate():
		t.queue_free()
	await physics_frame
	var round: RoundController = game.get("_round")
	var camera: Camera3D = game.get("_camera")
	root.get_node("HitBus").emit_hit(HitEvent.create(Vector2.ZERO, 0.7, "test"))  # start the round
	await physics_frame
	var walker: RangeTarget = game.spawn_target(RangeTarget.Kind.DEPTH, false, 4.6)
	for i in 60:
		await physics_frame
	var bull := RangeTarget.BULL_CENTER
	var aim := walker.body.to_global(Vector3(bull.x, bull.y, RangeTarget.THICKNESS / 2.0))
	root.get_node("HitBus").emit_hit(HitEvent.create(camera.unproject_position(aim), 0.7, "test"))
	for i in 60:
		await physics_frame
	# It keeps walking while the ball flies, so it may land a ring out: any
	# hit is at least (1 + moving bonus 1) = 2.
	var ok := round.throws == 1 and round.score >= 2
	_finish(ok, "kinds=%d most_at_once=%d walker_score=%d" % [seen.size(), most_at_once, round.score])


func _finish(ok: bool, detail: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + detail)
	quit(0 if ok else 1)
