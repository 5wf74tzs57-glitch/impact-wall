extends SceneTree
## Smoke test: does a hit on the target shatter it and score?
##
## Run from the project folder (no window needed):
##   godot --headless --path . -s res://tests/smoke_test.gd
## Prints PASS or FAIL and exits with code 0 (pass) or 1 (fail).

const SCENE := "res://games/target_practice/target_practice.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(game)
	for i in 10:
		await physics_frame

	var target: RigidBody3D = game.get("_target")
	var camera: Camera3D = game.get("_camera")
	if target == null or camera == null:
		_finish(false, "scene did not create a target and camera")
		return

	# Hit the middle of the target, exactly as a tap would.
	var point := camera.unproject_position(target.global_position)
	root.get_node("HitBus").emit_hit(HitEvent.create(point, 0.7, "test"))

	for i in 90:  # about 1.5 seconds of physics
		await physics_frame

	var debris := game.find_child("Debris", true, false)
	var shattered := debris != null
	var pieces := debris.get_child_count() if shattered else 0
	var hits: int = game.get("_score")
	var throws: int = game.get("_throws")
	var ok := shattered and pieces >= 10 and hits == 1 and throws == 1
	_finish(ok, "shattered=%s pieces=%d hits=%d throws=%d" % [shattered, pieces, hits, throws])


func _finish(ok: bool, detail: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + detail)
	quit(0 if ok else 1)
