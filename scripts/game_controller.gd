extends Node

## GameController — manages dummy note timing and judgement for TICKET 2.
## Attach as a child node of the Game scene.

signal judgement_emitted(grade: int, delta_ms: float)

const Judgement := preload("res://scripts/judgement.gd")

## Dummy note timing (Option A: fixed hit time)
var note_hit_time_sec: float = 2.0
var note_spawn_time_sec: float = 0.2
var miss_window_sec: float = 0.13   # auto-miss after hit_time + this

## State
var _start_ticks: int = 0
var _note_resolved: bool = false
var _running: bool = false

func start_run() -> void:
	_start_ticks = Time.get_ticks_msec()
	_note_resolved = false
	_running = true

func now_sec() -> float:
	return (Time.get_ticks_msec() - _start_ticks) / 1000.0

func is_note_active() -> bool:
	return _running and not _note_resolved

## Called from game_ui._process() to move the note toward the hit line.
## note_node: the ColorRect representing the note
## hitline_node: the ColorRect representing the hit line
## spawn_y: y position where note appears
func update_dummy_note(note_node: Control, hitline_node: Control, spawn_y: float) -> void:
	if not _running:
		return

	var t: float = now_sec()

	# Show note only after spawn time
	if t < note_spawn_time_sec:
		note_node.visible = false
		return

	note_node.visible = true

	if _note_resolved:
		return

	# Auto-miss check
	if t > note_hit_time_sec + miss_window_sec:
		_note_resolved = true
		judgement_emitted.emit(Judgement.Grade.MISS, 999.0)
		return

	# Interpolate note position: spawn_y -> hitline_y
	var hitline_y: float = hitline_node.position.y
	var travel_duration: float = note_hit_time_sec - note_spawn_time_sec
	var progress: float = clampf((t - note_spawn_time_sec) / travel_duration, 0.0, 1.0)
	note_node.position.y = lerpf(spawn_y, hitline_y, progress)

## Called when user taps. Returns the grade.
func handle_tap() -> int:
	if not _running or _note_resolved:
		return -1

	_note_resolved = true
	var t: float = now_sec()
	var delta_sec: float = t - note_hit_time_sec
	var delta_ms: float = delta_sec * 1000.0
	var grade: int = Judgement.get_grade(delta_ms)
	judgement_emitted.emit(grade, delta_ms)
	return grade
