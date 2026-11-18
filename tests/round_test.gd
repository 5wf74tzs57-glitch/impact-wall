extends SceneTree
## Round test: play a whole round of 10 throws and check the results screen
## is reached, the score adds up and the best score is saved.
##
##   godot --headless --path . -s res://tests/round_test.gd

const SCENE := "res://games/target_practice/target_practice.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(game)
	await _frames(10)
	var round: RoundController = game.get("_round")
	var camera: Camera3D = game.get("_camera")
	round.reset_best()

	_hit(Vector2.ZERO)  # start
	await _frames(5)
	for i in round.throws_per_round:
		if i % 2 == 0:
			# Even throws: wait for a target, then hit its middle.
			while not is_instance_valid(game.get("_target")) or game.get("_target_knocked"):
				await _frames(5)
			var target: RigidBody3D = game.get("_target")
			_hit(camera.unproject_position(target.global_position))
		else:
			_hit(camera.unproject_position(Vector3(-3.0, 3.5, -8.8)))  # back wall  # odd throws: miss
		await _frames(100)

	var cfg := ConfigFile.new()
	cfg.load(RoundController.SAVE_PATH)
	var saved: int = cfg.get_value("best", "target_practice", -1)
	var ok := round.state == RoundController.State.RESULTS and round.throws == 10 \
		and round.hits == 5 and round.score == 15 and saved == 15
	print(("PASS: " if ok else "FAIL: ") + "state=%d throws=%d hits=%d score=%d saved_best=%d"
		% [round.state, round.throws, round.hits, round.score, saved])
	round.reset_best()
	quit(0 if ok else 1)


func _hit(point: Vector2) -> void:
	root.get_node("HitBus").emit_hit(HitEvent.create(point, 0.7, "test"))


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
