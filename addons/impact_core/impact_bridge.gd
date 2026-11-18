class_name ImpactBridge
extends Node3D
## Turns hits into virtual balls flying into the 3D scene.
##
## The key idea: the projected wall IS the camera's view. A hit at a point on
## the wall becomes a ball launched from the camera, through that point, into
## the scene, faster for harder hits. Target practice, tower games and sports
## games all start from this.

## Emitted right after a ball is launched for a hit.
signal ball_launched(ball: RigidBody3D, event: HitEvent)

## The camera whose view is projected on the wall.
@export var camera: Camera3D
## Ball speed for the softest hit, in meters per second.
@export var min_speed: float = 14.0
## Ball speed for the hardest hit, in meters per second.
@export var max_speed: float = 30.0
@export var ball_radius: float = 0.12
@export var ball_mass: float = 0.5
@export var ball_color: Color = Color(1.0, 0.45, 0.2)
## Seconds before a ball is removed.
@export var ball_lifetime: float = 4.0
## Oldest balls are removed past this count, to keep phones fast.
@export var max_balls: int = 10
## Show an instant flash where the hit landed, so the game feels responsive
## even while the ball is still flying.
@export var show_hit_flash: bool = true
## When false, hits are ignored (no ball, no flash), e.g. on a game's
## start or results screen, where a hit means "start" rather than "throw".
@export var enabled: bool = true

var _balls: Array[RigidBody3D] = []
var _flash_layer: CanvasLayer
var _ball_mesh: SphereMesh
var _ball_shape: SphereShape3D
var _ball_material: StandardMaterial3D


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = ball_radius
	_ball_mesh.height = ball_radius * 2.0
	_ball_shape = SphereShape3D.new()
	_ball_shape.radius = ball_radius
	_ball_material = StandardMaterial3D.new()
	_ball_material.albedo_color = ball_color
	_ball_mesh.material = _ball_material

	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 10
	add_child(_flash_layer)

	HitBus.hit.connect(_on_hit)


func _on_hit(event: HitEvent) -> void:
	if not enabled:
		return
	if camera == null:
		push_warning("ImpactBridge: no camera set, ignoring hit.")
		return
	if show_hit_flash:
		_spawn_flash(event)
	_launch_ball(event)


func _launch_ball(event: HitEvent) -> void:
	var origin := camera.project_ray_origin(event.screen_pos)
	var direction := camera.project_ray_normal(event.screen_pos)

	var ball := RigidBody3D.new()
	ball.mass = ball_mass
	ball.continuous_cd = true  # Fast balls must not pass through thin targets.
	# Fly in a straight line until the first contact, so the ball strikes
	# exactly what was under the hit point; then gravity takes over.
	ball.gravity_scale = 0.0
	ball.contact_monitor = true
	ball.max_contacts_reported = 1
	ball.body_entered.connect(func(_body: Node) -> void: ball.gravity_scale = 1.0, CONNECT_ONE_SHOT)

	var shape := CollisionShape3D.new()
	shape.shape = _ball_shape
	ball.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _ball_mesh
	ball.add_child(mesh)

	add_child(ball)
	ball.global_position = origin + direction * (camera.near + ball_radius * 2.0)
	ball.linear_velocity = direction * lerpf(min_speed, max_speed, event.force)

	_balls.append(ball)
	while _balls.size() > max_balls:
		var oldest: RigidBody3D = _balls.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	get_tree().create_timer(ball_lifetime).timeout.connect(_remove_ball.bind(ball))

	ball_launched.emit(ball, event)


func _remove_ball(ball) -> void:
	# Untyped on purpose: the ball may already have been freed by max_balls.
	if not is_instance_valid(ball):
		return
	_balls.erase(ball)
	ball.queue_free()


func _spawn_flash(event: HitEvent) -> void:
	var flash := HitFlash.new()
	flash.position = event.screen_pos
	_flash_layer.add_child(flash)


## A ring that pops out from the hit point and fades away.
class HitFlash:
	extends Node2D

	var radius: float = 18.0

	func _ready() -> void:
		var tween := create_tween().set_parallel(true)
		tween.tween_property(self, "scale", Vector2(2.5, 2.5), 0.25)
		tween.tween_property(self, "modulate:a", 0.0, 0.25)
		tween.chain().tween_callback(queue_free)

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color.WHITE, 4.0, true)
