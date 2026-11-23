extends SceneTree
## Round test: play a whole round of 10 throws and check the results screen
## is reached, the score adds up and the best score is saved.
##
##   godot --headless --path . -s res://tests/round_test.gd

const SCENE := "res://games/target_practice/target_practice.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)  # The real 16:9 screen shape (headless defaults to square).
	var game: Node3D = (load(SCENE) as PackedScene).instantiate()
	game.set("auto_spawn", false)
	root.add_child(game)
	await _frames(10)
	var round: RoundController = game.get("_round")
	var camera: Camera3D = game.get("_camera")
	round.reset_best()

	_hit(Vector2.ZERO)  # start
	await _frames(5)
	var xs := [-2.6, -0.9, 0.9, 2.6]
	for i in round.throws_per_round:
		if i % 2 == 0:
			# Even throws: a near pop-up rises, hit its bullseye (+5).
			var target: RangeTarget = game.spawn_target(RangeTarget.Kind.POP_UP, false, xs[(i / 2) % xs.size()], -5.0)
			await _frames(40)
			var bull := RangeTarget.BULL_CENTER
			_hit(camera.unproject_position(target.body.to_global(Vector3(bull.x, bull.y, RangeTarget.THICKNESS / 2.0))))
		else:
			_hit(camera.unproject_position(Vector3(-1.0, 0.0, -3.0)))  # odd throws: miss
		await _frames(80)

	var cfg := ConfigFile.new()
	cfg.load(RoundController.SAVE_PATH)
	var saved: int = cfg.get_value("best", "target_practice", -1)
	var ok := round.state == RoundController.State.RESULTS and round.throws == 10 \
		and round.hits == 5 and round.score == 25 and saved == 25
	print(("PASS: " if ok else "FAIL: ") + "state=%d throws=%d hits=%d score=%d saved_best=%d"
		% [round.state, round.throws, round.hits, round.score, saved])
	round.reset_best()
	quit(0 if ok else 1)


func _hit(point: Vector2) -> void:
	root.get_node("HitBus").emit_hit(HitEvent.create(point, 0.7, "test"))


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
