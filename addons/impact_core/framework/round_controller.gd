class_name RoundController
extends Node
## Runs a round of a game: ready → playing → results → ready again.
##
## A round is a set number of throws, not a time limit, because players walk
## up to collect the ball after each throw. Any hit starts a round from the
## ready screen, or starts a new one from the results screen. The best score
## is saved on the device.
##
## Games tell it how each throw went with `record_throw(points)`.

enum State { READY, PLAYING, RESULTS }

signal round_started
## One throw was scored (0 = miss). `throws_left` counts down to 0.
signal throw_recorded(points: int, throws_left: int)
signal round_finished(score: int, best: int, is_new_best: bool)

const SAVE_PATH := "user://scores.cfg"

## Name used to save this game's best score.
@export var game_id: String = "game"
@export var throws_per_round: int = 10
## Seconds after the results appear before a hit can start a new round, so a
## ball still in flight doesn't skip the results screen.
@export var restart_delay: float = 1.5

var state: State = State.READY
var score := 0
var throws := 0
var hits := 0
var best := 0

var _finished_at_ms := 0


func _ready() -> void:
	best = _load_best()
	# Looked up at run time (not by name) so test scripts can load this class
	# before Godot has set up the HitBus autoload.
	get_node("/root/HitBus").hit.connect(_on_hit)


func throws_left() -> int:
	return throws_per_round - throws


## Start a new round now (also happens on any hit while not playing).
func start() -> void:
	state = State.PLAYING
	score = 0
	throws = 0
	hits = 0
	round_started.emit()


## Record one throw. Points of 0 means a miss.
func record_throw(points: int) -> void:
	if state != State.PLAYING:
		return
	throws += 1
	score += points
	if points > 0:
		hits += 1
	throw_recorded.emit(points, throws_left())
	if throws >= throws_per_round:
		_finish()


## Forget the saved best score (used by tests).
func reset_best() -> void:
	best = 0
	_save_best()


func _on_hit(_event: HitEvent) -> void:
	var can_restart := state == State.RESULTS \
		and Time.get_ticks_msec() - _finished_at_ms >= int(restart_delay * 1000.0)
	if state == State.READY or can_restart:
		# Wait a frame so the hit that starts the round isn't also a throw.
		start.call_deferred()


func _finish() -> void:
	state = State.RESULTS
	_finished_at_ms = Time.get_ticks_msec()
	var is_new_best := score > best
	if is_new_best:
		best = score
		_save_best()
	round_finished.emit(score, best, is_new_best)


func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0
	return int(cfg.get_value("best", game_id, 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # Keep other games' scores; fine if the file is new.
	cfg.set_value("best", game_id, best)
	cfg.save(SAVE_PATH)
