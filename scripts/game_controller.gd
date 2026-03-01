extends Node

## GameController — 3-lane chart-driven multi-note spawning + judgement.
## TICKET 8: adds cursor_lane + MOVING note auto-judge.

signal judgement_emitted(grade: int, delta_ms: float)
signal run_finished()

const Judgement := preload("res://scripts/judgement.gd")
const ChartLoader := preload("res://scripts/chart_loader.gd")
const NoteViewScript := preload("res://scripts/note_view.gd")

const DEBUG := false
const NUM_LANES := 3
const MISS_WINDOW_SEC := 0.13

## Chart data
var _chart_notes: Array = []
var _approach_time: float = 1.2
var _spawn_index: int = 0

## Active notes: [{t, type, lane, span, diag, len, view, judged}]
var _active_notes: Array = []

## State
var _start_ticks: int = 0
var _running: bool = false

## Lane geometry (set by game_ui)
var lane_centers_x: Array = []
var spawn_y: float = 200.0
var hitline_y: float = 1400.0
var notes_layer: Control = null

## TICKET 8: held lane for moving notes (set by game_ui each frame)
var cursor_lane: int = 1

## TICKET 5: judgement counters
var _count_perfect: int = 0
var _count_excellent: int = 0
var _count_good: int = 0
var _count_soso: int = 0
var _count_miss: int = 0

func start_run(diff: String = "normal") -> void:
	var chart: Dictionary = ChartLoader.load_chart("track01", diff)
	_chart_notes = chart.get("notes", [])
	_approach_time = chart.get("approach_time", 1.2)
	_spawn_index = 0
	_clear_active_notes()
	_reset_counters()
	cursor_lane = 1
	_start_ticks = Time.get_ticks_msec()
	_running = true

func stop_run() -> void:
	_running = false
	_clear_active_notes()

func now_sec() -> float:
	return (Time.get_ticks_msec() - _start_ticks) / 1000.0

func is_running() -> bool:
	return _running

func process_update() -> void:
	if not _running:
		return
	var t: float = now_sec()
	_spawn_pending_notes(t)
	_update_active_notes(t)
	_check_run_complete()

## ---- Input handlers ----

func handle_tap(lane: int) -> int:
	return _judge_nearest("tap", lane, -1)

func handle_scratch(lane_pair: int) -> int:
	return _judge_nearest("scratch", lane_pair, -1)

## ---- Run summary (TICKET 5) ----

func get_run_summary() -> Dictionary:
	var total: int = _count_perfect + _count_excellent + _count_good + _count_soso + _count_miss
	if total == 0:
		return {"rank": "D", "perfect": 0, "excellent": 0, "good": 0, "soso": 0, "miss": 0, "total": 0}
	var miss_r: float = float(_count_miss) / float(total)
	var perf_r: float = float(_count_perfect) / float(total)
	var pe_r: float = float(_count_perfect + _count_excellent) / float(total)
	var peg_r: float = float(_count_perfect + _count_excellent + _count_good) / float(total)
	var rank: String = "C"
	if miss_r >= 0.25:
		rank = "D"
	elif perf_r >= 0.5 and _count_miss == 0:
		rank = "S"
	elif pe_r >= 0.6:
		rank = "A"
	elif peg_r >= 0.7:
		rank = "B"
	return {"rank": rank, "perfect": _count_perfect, "excellent": _count_excellent,
		"good": _count_good, "soso": _count_soso, "miss": _count_miss, "total": total}

## ---- Internal ----

func _spawn_pending_notes(t: float) -> void:
	while _spawn_index < _chart_notes.size():
		var nd: Dictionary = _chart_notes[_spawn_index]
		var note_t: float = float(nd.get("t", 0.0))
		if note_t - _approach_time > t:
			break
		_spawn_note(nd)
		_spawn_index += 1

func _update_active_notes(t: float) -> void:
	var to_remove: Array = []
	for i in range(_active_notes.size()):
		var entry: Dictionary = _active_notes[i]
		if entry.get("judged", false):
			continue
		var entry_t: float = float(entry.get("t", 0.0))
		var entry_type: String = str(entry.get("type", "tap"))

		# MOVING notes: auto-judge at hit time
		if entry_type == "moving":
			if t >= entry_t:
				entry["judged"] = true
				var delta_ms: float = (t - entry_t) * 1000.0
				var grade: int
				if absf(delta_ms) <= 130.0 and cursor_lane == int(entry.get("lane", -1)):
					grade = Judgement.get_grade(delta_ms)
				else:
					grade = Judgement.Grade.MISS
				_inc(grade)
				judgement_emitted.emit(grade, delta_ms)
				_free_view(entry)
				to_remove.append(i)
				continue
			# Move visual
			_move_note_view(entry, t)
			continue

		# TAP / SCRATCH: auto-miss after window
		if t > entry_t + MISS_WINDOW_SEC:
			entry["judged"] = true
			var miss_delta: float = (t - entry_t) * 1000.0
			_inc(Judgement.Grade.MISS)
			judgement_emitted.emit(Judgement.Grade.MISS, miss_delta)
			_free_view(entry)
			to_remove.append(i)
			continue
		_move_note_view(entry, t)
	_remove_indices(to_remove)

func _move_note_view(n: Dictionary, t: float) -> void:
	var view: Control = n.get("view")
	if not view or not is_instance_valid(view):
		return
	var note_t: float = float(n.get("t", 0.0))
	var spawn_t: float = note_t - _approach_time
	var progress: float = clampf((t - spawn_t) / _approach_time, 0.0, 1.0)
	var y: float = lerpf(spawn_y, hitline_y, progress) - view.size.y * 0.5
	var x: float = _get_note_x(n) - view.size.x * 0.5
	view.position = Vector2(x, y)

func _get_note_x(n: Dictionary) -> float:
	var ntype: String = str(n.get("type", "tap"))
	var lane: int = int(n.get("lane", 1))
	if ntype == "scratch":
		var l0: int = clampi(lane, 0, NUM_LANES - 2)
		if lane_centers_x.size() > l0 + 1:
			return (lane_centers_x[l0] + lane_centers_x[l0 + 1]) * 0.5
	if lane_centers_x.size() > lane:
		return lane_centers_x[lane]
	return 540.0

func _judge_nearest(input_type: String, input_lane: int, _unused: int) -> int:
	if not _running:
		return -1
	var t: float = now_sec()
	var best_i: int = -1
	var best_abs: float = 999999.0
	for i in range(_active_notes.size()):
		var candidate: Dictionary = _active_notes[i]
		if candidate.get("judged", false):
			continue
		if str(candidate.get("type", "")) != input_type:
			continue
		if int(candidate.get("lane", -1)) != input_lane:
			continue
		var c_delta: float = absf((t - float(candidate.get("t", 0.0))) * 1000.0)
		if c_delta <= 130.0 and c_delta < best_abs:
			best_abs = c_delta
			best_i = i
	if best_i == -1:
		return -1
	var matched: Dictionary = _active_notes[best_i]
	matched["judged"] = true
	var matched_delta: float = (t - float(matched.get("t", 0.0))) * 1000.0
	var grade: int = Judgement.get_grade(matched_delta)
	_inc(grade)
	judgement_emitted.emit(grade, matched_delta)
	_free_view(matched)
	_active_notes.remove_at(best_i)
	return grade

func _spawn_note(nd: Dictionary) -> void:
	if not notes_layer or not is_instance_valid(notes_layer):
		return
	var ntype: String = str(nd.get("type", "tap"))
	var view: Control = NoteViewScript.new()
	var diag_str: String = str(nd.get("diag", "\\"))
	var note_lane: int = int(nd.get("lane", 0))
	var len_sec: float = float(nd.get("len", 0.6))
	view.setup(ntype, diag_str, note_lane, len_sec)
	notes_layer.add_child(view)
	_active_notes.append({
		"t": float(nd.get("t", 0.0)),
		"type": ntype,
		"lane": int(nd.get("lane", 0)),
		"span": int(nd.get("span", 1)),
		"diag": diag_str,
		"len": len_sec,
		"view": view,
		"judged": false,
	})

func _check_run_complete() -> void:
	if _spawn_index >= _chart_notes.size() and _active_notes.is_empty():
		_running = false
		run_finished.emit()

func _free_view(n: Dictionary) -> void:
	var v: Control = n.get("view")
	if v and is_instance_valid(v):
		v.queue_free()

func _clear_active_notes() -> void:
	for n in _active_notes:
		_free_view(n)
	_active_notes.clear()

func _remove_indices(indices: Array) -> void:
	indices.sort()
	indices.reverse()
	for idx in indices:
		_active_notes.remove_at(idx)

func _reset_counters() -> void:
	_count_perfect = 0
	_count_excellent = 0
	_count_good = 0
	_count_soso = 0
	_count_miss = 0

func _inc(grade: int) -> void:
	match grade:
		Judgement.Grade.PERFECT: _count_perfect += 1
		Judgement.Grade.EXCELLENT: _count_excellent += 1
		Judgement.Grade.GOOD: _count_good += 1
		Judgement.Grade.SO_SO: _count_soso += 1
		Judgement.Grade.MISS: _count_miss += 1
