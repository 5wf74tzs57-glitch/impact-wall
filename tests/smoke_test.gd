extends SceneTree
## Smoke test: on the outdoor range, start a round, hit a pop-up's bullseye
## (+3), hit a friendly (-3), then miss (0).
##
## Run from the project folder (no window needed):
##   godot --headless --path . -s res://tests/smoke_test.gd
## Prints PASS or FAIL and exits with code 0 (pass) or 1 (fail).

const SCENE := "res://games/target_practice/target_practice.tscn"

var game: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = (load(SCENE) as PackedScene).instantiate()
	game.set("auto_spawn", false)  # Only the targets this test makes.
	root.add_child(game)
	await _frames(10)
	var round: RoundController = game.get("_round")
	var camera: Camera3D = game.get("_camera")

	# 1. Any hit on the start screen starts the round (and throws nothing).
	_hit(Vector2.ZERO)
	await _frames(5)
	if round.state != RoundController.State.PLAYING or game.get("_balls_launched") != 0:
		_finish(false, "first hit should start the round without throwing")
		return

	# 2. A pop-up rises; hit its middle: it shatters and scores 3.
	var target: RangeTarget = game.spawn_target(RangeTarget.Kind.POP_UP, false, -1.05)
	await _frames(40)
	_hit(camera.unproject_position(target.body.global_position))
	await _frames(60)
	var debris := game.find_child("Debris", true, false)
	var pieces := debris.get_child_count() if debris != null else 0
	if pieces < 10 or round.throws != 1 or round.score != 3:
		_finish(false, "bullseye: pieces=%d throws=%d score=%d" % [pieces, round.throws, round.score])
		return

	# 3. A friendly pops up; hitting it costs 3.
	var friendly: RangeTarget = game.spawn_target(RangeTarget.Kind.POP_UP, true, 1.45)
	await _frames(40)
	_hit(camera.unproject_position(friendly.body.global_position))
	await _frames(60)
	if round.throws != 2 or round.score != 0:
		_finish(false, "friendly: throws=%d score=%d" % [round.throws, round.score])
		return

	# 4. Throw at the grass in front: a miss, worth 0.
	_hit(camera.unproject_position(Vector3(-1.0, 0.0, -3.0)))
	await _frames(90)
	var ok := round.throws == 3 and round.score == 0 and round.hits == 1
	_finish(ok, "pieces=%d throws=%d score=%d hits=%d" % [pieces, round.throws, round.score, round.hits])


func _hit(point: Vector2) -> void:
	root.get_node("HitBus").emit_hit(HitEvent.create(point, 0.7, "test"))


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _finish(ok: bool, detail: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + detail)
	quit(0 if ok else 1)
