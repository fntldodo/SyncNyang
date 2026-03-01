extends Node

## GameController — 3-lane chart-driven judgement.
## TICKET 8.2: 꾹꾹 long note = press-hold-release with time-based consume visual.

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

## Active notes
var _active_notes: Array = []

## State
var _start_ticks: int = 0
var _running: bool = false

## Lane geometry (set by game_ui)
var lane_centers_x: Array = []
var spawn_y: float = 200.0
var hitline_y: float = 1400.0
var notes_layer: Control = null

## Hit zone half-height for candidate prioritization (set by game_ui)
var hit_zone_half_h: float = 55.0

## Held lane + holding state (set by game_ui each frame)
var cursor_lane: int = 1
var cursor_holding: bool = false

## Judgement counters
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
	cursor_holding = false
	_start_ticks = Time.get_ticks_msec()
	_running = true

func stop_run() -> void:
	_running = false
	_clear_active_notes()

func now_sec() -> float:
	return (Time.get_ticks_msec() - _start_ticks) / 1000.0

func is_running() -> bool:
	return _running

func get_approach_time() -> float:
	return _approach_time

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

## TICKET 8.2: press on a lane → start a 꾹꾹 hold
func handle_moving_press(lane: int) -> void:
	if not _running:
		return
	var t: float = now_sec()
	for entry in _active_notes:
		if entry.get("judged", false):
			continue
		if str(entry.get("type", "")) != "moving":
			continue
		if int(entry.get("lane", -1)) != lane:
			continue
		if str(entry.get("m_state", "idle")) != "idle":
			continue
		var start_t: float = float(entry.get("t", 0.0))
		var delta_ms: float = (t - start_t) * 1000.0
		if absf(delta_ms) <= 130.0:
			entry["m_state"] = "holding"
			entry["start_grade"] = Judgement.get_grade(delta_ms)
			return

## TICKET 8.2: release on a lane → end a 꾹꾹 hold
func handle_moving_release(lane: int) -> void:
	if not _running:
		return
	var t: float = now_sec()
	for entry in _active_notes:
		if entry.get("judged", false):
			continue
		if str(entry.get("type", "")) != "moving":
			continue
		if str(entry.get("m_state", "")) != "holding":
			continue
		# Release matches this holding note (same lane or any — only one active per lane)
		if int(entry.get("lane", -1)) != lane:
			continue
		var end_t: float = float(entry.get("t", 0.0)) + float(entry.get("len", 1.2))
		var end_delta_ms: float = (t - end_t) * 1000.0
		var end_grade: int
		if absf(end_delta_ms) <= 130.0:
			end_grade = Judgement.get_grade(end_delta_ms)
		else:
			end_grade = Judgement.Grade.MISS
		_finish_moving(entry, end_grade, end_delta_ms)
		return

## ---- Run summary ----

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
			to_remove.append(i)
			continue
		var entry_t: float = float(entry.get("t", 0.0))
		var entry_type: String = str(entry.get("type", "tap"))

		# ---- 꾹꾹 (moving) long notes ----
		if entry_type == "moving":
			var entry_len: float = float(entry.get("len", 1.2))
			var end_t: float = entry_t + entry_len
			var m_state: String = str(entry.get("m_state", "idle"))
			var on_lane: bool = cursor_holding and cursor_lane == int(entry.get("lane", -1))

			# Time progress for visual (always advances, independent of hold)
			var time_prog: float = clampf((t - entry_t) / entry_len, 0.0, 1.0)

			# Sampling during hold
			if m_state == "holding" and t >= entry_t and t <= end_t:
				entry["total_samples"] = int(entry.get("total_samples", 0)) + 1
				if on_lane:
					entry["good_samples"] = int(entry.get("good_samples", 0)) + 1

			# Auto-miss: idle and past start window
			if m_state == "idle" and t > entry_t + MISS_WINDOW_SEC:
				_miss_moving(entry)
				to_remove.append(i)
				continue

			# Auto-miss: holding but past end window (never released)
			if m_state == "holding" and t > end_t + MISS_WINDOW_SEC:
				_finish_moving(entry, Judgement.Grade.MISS, (t - end_t) * 1000.0)
				to_remove.append(i)
				continue

			# Check if already ended this frame
			if entry.get("judged", false):
				to_remove.append(i)
				continue

			# Update NoteView visual state
			var view: Control = entry.get("view")
			if view and is_instance_valid(view):
				view.time_progress = time_prog
				view.on_track_now = on_lane and m_state == "holding"
				view.in_hold_window = t >= entry_t and t <= end_t
				view.near_end = t >= (end_t - 0.3) and t <= (end_t + MISS_WINDOW_SEC)
				view.is_holding = m_state == "holding"
				view.queue_redraw()

			_move_note_view(entry, t)
			continue

		# ---- TAP / SCRATCH: auto-miss after window ----
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

func _miss_moving(entry: Dictionary) -> void:
	entry["judged"] = true
	entry["m_state"] = "ended"
	_inc(Judgement.Grade.MISS)
	var delta: float = (now_sec() - float(entry.get("t", 0.0))) * 1000.0
	judgement_emitted.emit(Judgement.Grade.MISS, delta)
	_free_view(entry)

func _finish_moving(entry: Dictionary, end_grade: int, end_delta_ms: float) -> void:
	entry["judged"] = true
	entry["m_state"] = "ended"
	var start_grade: int = int(entry.get("start_grade", Judgement.Grade.MISS))
	var total_s: int = int(entry.get("total_samples", 0))
	var good_s: int = int(entry.get("good_samples", 0))
	var hold_ratio: float = float(good_s) / maxf(float(total_s), 1.0)

	# Combined grade: start + end + hold ratio
	var final_grade: int = Judgement.Grade.MISS
	if start_grade <= Judgement.Grade.PERFECT and end_grade <= Judgement.Grade.PERFECT and hold_ratio >= 0.95:
		final_grade = Judgement.Grade.PERFECT
	elif start_grade <= Judgement.Grade.EXCELLENT and end_grade <= Judgement.Grade.EXCELLENT and hold_ratio >= 0.90:
		final_grade = Judgement.Grade.EXCELLENT
	elif start_grade <= Judgement.Grade.GOOD and end_grade <= Judgement.Grade.GOOD and hold_ratio >= 0.80:
		final_grade = Judgement.Grade.GOOD

	_inc(final_grade)
	judgement_emitted.emit(final_grade, absf(end_delta_ms))
	_free_view(entry)

func _move_note_view(n: Dictionary, t: float) -> void:
	var view: Control = n.get("view")
	if not view or not is_instance_valid(view):
		return
	var note_t: float = float(n.get("t", 0.0))
	var spawn_t: float = note_t - _approach_time
	var progress: float = clampf((t - spawn_t) / _approach_time, 0.0, 1.0)
	var note_bottom_y: float = lerpf(spawn_y, hitline_y, progress)
	var y: float = note_bottom_y - view.size.y
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
	# Collect all valid candidates within timing window
	var in_zone_i: int = -1
	var in_zone_abs: float = 999999.0
	var out_zone_i: int = -1
	var out_zone_abs: float = 999999.0
	for i in range(_active_notes.size()):
		var candidate: Dictionary = _active_notes[i]
		if candidate.get("judged", false):
			continue
		if str(candidate.get("type", "")) != input_type:
			continue
		if int(candidate.get("lane", -1)) != input_lane:
			continue
		var c_delta: float = absf((t - float(candidate.get("t", 0.0))) * 1000.0)
		if c_delta > 130.0:
			continue
		if _is_note_in_zone(candidate, t):
			if c_delta < in_zone_abs:
				in_zone_abs = c_delta
				in_zone_i = i
		else:
			if c_delta < out_zone_abs:
				out_zone_abs = c_delta
				out_zone_i = i
	# Prefer in-zone, fall back to out-zone
	var best_i: int = in_zone_i if in_zone_i >= 0 else out_zone_i
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

func _is_note_in_zone(n: Dictionary, t: float) -> bool:
	var note_t: float = float(n.get("t", 0.0))
	var spawn_t: float = note_t - _approach_time
	var progress: float = clampf((t - spawn_t) / _approach_time, 0.0, 1.0)
	var note_y: float = lerpf(spawn_y, hitline_y, progress)
	return absf(note_y - hitline_y) <= hit_zone_half_h

func _spawn_note(nd: Dictionary) -> void:
	if not notes_layer or not is_instance_valid(notes_layer):
		return
	var ntype: String = str(nd.get("type", "tap"))
	var view: Control = NoteViewScript.new()
	var diag_str: String = str(nd.get("diag", "\\"))
	var note_lane: int = int(nd.get("lane", 0))
	var len_sec: float = float(nd.get("len", 1.2))
	var travel_dist: float = hitline_y - spawn_y
	view.setup(ntype, diag_str, note_lane, len_sec, _approach_time, travel_dist)
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
		"m_state": "idle",
		"start_grade": Judgement.Grade.MISS,
		"good_samples": 0,
		"total_samples": 0,
	})

func _check_run_complete() -> void:
	if _spawn_index >= _chart_notes.size() and _active_notes.is_empty():
		_running = false
		run_finished.emit()

func _free_view(n: Dictionary) -> void:
	var v = n.get("view")
	if v != null and v is Control and is_instance_valid(v):
		v.queue_free()
	n["view"] = null

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
