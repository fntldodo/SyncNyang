extends Node

## GameController — 3-lane chart-driven judgement.
## TICKET 8.2: 꾹꾹 long note = press-hold-release with time-based consume visual.

signal judgement_emitted(grade: int, delta_ms: float)
signal run_finished()
signal gauge_changed(value: float)
signal fever_started()
signal fever_ended()
signal score_changed(score: int, combo: int)
signal fever_door_opened(bonus: int)

const Judgement := preload("res://scripts/judgement.gd")
const ChartLoader := preload("res://scripts/chart_loader.gd")
const NoteViewScript := preload("res://scripts/note_view.gd")

const DEBUG := false
const NUM_LANES := 3
const MISS_WINDOW_SEC := 0.20

## Audio latency offset (loaded from SaveData at start_run)
var input_offset_ms: float = 0.0

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
var lane_centers_x: Array = []       # Hitline centers (legacy/fallback)
var lane_centers_top: Array = []      # Top/Spawn centers
var lane_centers_bottom: Array = []   # Bottom centers
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

## Churu gauge + Fever (TICKET 10)
const GAUGE_MAX := 200.0
const FEVER_DURATION := 8.0
const FEVER_MULTIPLIER := 1.2
const GAUGE_GAIN := {0: 15.0, 1: 12.0, 2: 8.0, 3: 4.0, 4: -2.0}  # PERFECT..MISS
var gauge: float = 0.0
var is_fever: bool = false
var _fever_end_time: float = 0.0
var _fever_count: int = 0

## Score + Combo (TICKET 10-3)
const BASE_SCORE := 100
const SCORE_WEIGHT := {0: 1.0, 1: 0.9, 2: 0.75, 3: 0.5, 4: 0.0}  # PERFECT..MISS
var score: int = 0
var combo: int = 0
var fever_scratch_score: int = 0
const FEVER_SCRATCH_BONUS := 50
const DOOR_OPEN_BONUS := 500
var _fever_scratch_count: int = 0
var _fever_door_opened: bool = false
var _fever_time_offset: float = 0.0
var _fever_start_real_sec: float = 0.0
var _fever_time_unfrozen: bool = false
var fever_time_unfrozen: bool: get = get_fever_time_unfrozen
func get_fever_time_unfrozen() -> bool: return _fever_time_unfrozen
const DEBUG_FEVER_RESUME := true
const RESUME_MARGIN_SEC := 0.3 # Safety margin to ensure note enters from off-screen

func start_run(diff: String = "normal") -> void:
	var chart: Dictionary = ChartLoader.load_chart("track01", diff)
	_chart_notes = chart.get("notes", [])
	_approach_time = chart.get("approach_time", 1.2)
	_spawn_index = 0
	_clear_active_notes()
	_reset_counters()
	fever_scratch_score = 0
	gauge = 0.0
	is_fever = false
	_fever_end_time = 0.0
	_fever_count = 0
	cursor_lane = 1
	cursor_holding = false
	_fever_time_offset = 0.0
	_fever_start_real_sec = 0.0
	_fever_time_unfrozen = false
	input_offset_ms = SaveData.input_offset_ms
	_start_ticks = Time.get_ticks_msec()
	_running = true

func stop_run() -> void:
	_running = false
	_clear_active_notes()

func now_sec() -> float:
	var real_sec: float = (Time.get_ticks_msec() - _start_ticks) / 1000.0
	# Time is frozen only if in fever AND the door hasn't been opened yet.
	if is_fever and not _fever_time_unfrozen:
		return _fever_start_real_sec - _fever_time_offset
	return real_sec - _fever_time_offset

func is_running() -> bool:
	return _running

func get_approach_time() -> float:
	return _approach_time

func process_update() -> void:
	if not _running:
		return
	var t: float = now_sec()
	# 1. Update fever state and handle time offsets first
	_update_fever(t)
	
	# t might need to be re-evaluated since _update_fever could have fast-forwarded now_sec()
	if not is_fever:
		t = now_sec()
	
	# 2. Spawn incoming notes using the corrected time
	_spawn_pending_notes(t)
	
	# 3. Update active notes (movement and auto-miss)
	# Use normal movement if not in fever OR if time was unfrozen early
	if not is_fever or _fever_time_unfrozen:
		_update_active_notes(t)
	else:
		_update_active_notes_fever_frozen(t)
		
	# 4. Check if run is over
	_check_run_complete()

## ---- Input handlers ----

func handle_tap(lane: int) -> int:
	return _judge_nearest("tap", lane, -1)

## Fever-only free scratch: each swipe adds a scratch to the door
func handle_fever_scratch() -> int:
	if not _running or not is_fever:
		return 0
	_fever_scratch_count += 1
	fever_scratch_score += FEVER_SCRATCH_BONUS
	score += FEVER_SCRATCH_BONUS
	score_changed.emit(score, combo)
	return _fever_scratch_count

## Called by game_ui when fever door is opened
func award_door_bonus() -> void:
	score += DOOR_OPEN_BONUS
	_fever_door_opened = true
	score_changed.emit(score, combo)
	fever_door_opened.emit(DOOR_OPEN_BONUS)
	
	# Resume notes immediately even if the 8s fever duration isn't up!
	_unfreeze_fever_time()

func _unfreeze_fever_time() -> void:
	if not is_fever or _fever_time_unfrozen:
		return
	
	var current_real_sec: float = (Time.get_ticks_msec() - _start_ticks) / 1000.0
	var elapsed_fever: float = current_real_sec - _fever_start_real_sec
	
	# Unfreeze logic: bake the elapsed fever duration into the offset
	_fever_time_offset += elapsed_fever
	_fever_time_unfrozen = true
	
	# Fast-forward to the NEXT note spawn so there's no chart gap.
	# Lead target is (next_note_t - approach_time - margin) to enter from off-screen.
	if _spawn_index < _chart_notes.size():
		var next_note_t: float = float(_chart_notes[_spawn_index].get("t", 0.0))
		var target_resume_t: float = next_note_t - (_approach_time + RESUME_MARGIN_SEC)
		var gap: float = target_resume_t - now_sec()
		
		# Only jump forward. If gap is negative, it means a note should have already spawned.
		if gap > 0.0:
			_fever_time_offset -= gap
			if DEBUG_FEVER_RESUME:
				print("[DEBUG FEVER] Time unfrozen. Gap %.3fs. Fast-forwarding to off-screen spawn." % gap)
		elif DEBUG_FEVER_RESUME:
			print("[DEBUG FEVER] Time unfrozen. Next note already in range. No jump needed.")

## TICKET 8.2+8.3: press on a lane → start a 꾹꾹 hold (with late latch grace)
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
		var end_t: float = start_t + float(entry.get("len", 1.2))
		var delta_ms: float = (t - start_t) * 1000.0
		# Normal start: within ±130ms
		if absf(delta_ms) <= 130.0:
			entry["m_state"] = "holding"
			entry["start_grade"] = Judgement.get_grade(delta_ms)
			return
		# Late latch grace: after start window but before end_t
		if delta_ms > 130.0 and t < end_t:
			entry["m_state"] = "holding"
			if delta_ms <= 350.0:
				entry["start_grade"] = Judgement.Grade.GOOD
			else:
				entry["start_grade"] = Judgement.Grade.SO_SO
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
		"good": _count_good, "soso": _count_soso, "miss": _count_miss, "total": total,
		"score": score, "combo_max": combo, "fever_count": _fever_count,
		"fever_scratch_score": fever_scratch_score}

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

			# Auto-miss: idle and past end_t (never pressed at all — grace period expired)
			if m_state == "idle" and t > end_t:
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

## Fever-frozen variant: notes stay put, no auto-miss, no movement
func _update_active_notes_fever_frozen(_t: float) -> void:
	# During fever, notes are frozen — don't move them, don't auto-miss
	# Only update moving note visuals if they were in holding state
	for entry in _active_notes:
		if entry.get("judged", false):
			continue
		# Keep views where they are (no _move_note_view)

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
	# 1.0 = hitline, < 0.0 = spawning high up
	var progress: float = minf((t - spawn_t) / _approach_time, 1.0)
	var note_bottom_y: float = lerpf(spawn_y, hitline_y, progress)
	
	# Perspective X: Lerp between top and bottom lane centers
	var progress_clamped: float = clampf(progress, 0.0, 1.0)
	var x: float = _get_note_x_perspective(n, progress_clamped) - view.size.x * 0.5
	
	var y: float = note_bottom_y - view.size.y
	view.position = Vector2(x, y)

func _get_note_x_perspective(n: Dictionary, progress: float) -> float:
	var ntype: String = str(n.get("type", "tap"))
	var lane: int = int(n.get("lane", 1))
	
	# Determine start/end X for this lane
	var x_start := 540.0
	var x_end := 540.0
	
	if ntype == "scratch":
		var l0: int = clampi(lane, 0, NUM_LANES - 2)
		if lane_centers_top.size() > l0 + 1:
			x_start = (lane_centers_top[l0] + lane_centers_top[l0 + 1]) * 0.5
			x_end = (lane_centers_bottom[l0] + lane_centers_bottom[l0 + 1]) * 0.5
	else:
		if lane_centers_top.size() > lane:
			x_start = lane_centers_top[lane]
			x_end = lane_centers_bottom[lane]
			
	return lerpf(x_start, x_end, progress)

func _get_note_x(n: Dictionary) -> float:
	# Keep for legacy/initial spawn calcs if needed, but movement uses perspective
	var ntype: String = str(n.get("type", "tap"))
	var lane: int = int(n.get("lane", 1))
	if ntype == "scratch":
		var l0: int = clampi(lane, 0, NUM_LANES - 2)
		if lane_centers_bottom.size() > l0 + 1:
			return (lane_centers_bottom[l0] + lane_centers_bottom[l0 + 1]) * 0.5
	if lane_centers_bottom.size() > lane:
		return lane_centers_bottom[lane]
	return 540.0

func _judge_nearest(input_type: String, input_lane: int, _unused: int) -> int:
	if not _running:
		return -1
	# Apply audio latency offset: positive offset_ms means user hears late,
	# so we shift 'now' forward to compensate.
	var t: float = now_sec() + input_offset_ms / 1000.0
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
		# Widen the valid hit window for candidates to 300ms to be more forgiving for mobile touch lag etc
		if c_delta > 300.0:
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
		# Diagnostic: Why did we fail?
		var total_active := _active_notes.size()
		var type_matches := 0
		var lane_matches := 0
		for c in _active_notes:
			if str(c.get("type", "")) == input_type: type_matches += 1
			if int(c.get("lane", -1)) == input_lane: lane_matches += 1
		print("[JUDGE] No match. Type=%s Lane=%d | Active=%d TypeMatch=%d LaneMatch=%d" % [input_type, input_lane, total_active, type_matches, lane_matches])
		return -1
		
	var matched: Dictionary = _active_notes[best_i]
	matched["judged"] = true
	var matched_delta: float = (t - float(matched.get("t", 0.0))) * 1000.0
	var grade: int = Judgement.get_grade(matched_delta)
	
	print("[JUDGE] %s lane=%d best=%d delta_ms=%.1f grade=%d" % [input_type, input_lane, best_i, matched_delta, grade])
	
	_inc(grade)
	judgement_emitted.emit(grade, matched_delta)
	_free_view(matched)
	# Safely remove from index if it hasn't been cleared already
	if best_i >= 0 and _active_notes.size() > best_i:
		if _active_notes[best_i] == matched:
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
		SaveData.last_run_summary = get_run_summary() # SAVE STATS NOW
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
	score = 0
	combo = 0

func _inc(grade: int) -> void:
	match grade:
		Judgement.Grade.PERFECT: _count_perfect += 1
		Judgement.Grade.EXCELLENT: _count_excellent += 1
		Judgement.Grade.GOOD: _count_good += 1
		Judgement.Grade.SO_SO: _count_soso += 1
		Judgement.Grade.MISS: _count_miss += 1
	_update_gauge(grade)
	_update_score(grade)

## ---- Churu Gauge + Fever (TICKET 10) ----

func _update_gauge(grade: int) -> void:
	var gain: float = GAUGE_GAIN.get(grade, 0.0)
	gauge = clampf(gauge + gain, 0.0, GAUGE_MAX)
	gauge_changed.emit(gauge)
	if gauge >= GAUGE_MAX and not is_fever:
		_start_fever()

func _start_fever() -> void:
	is_fever = true
	gauge = 0.0
	# Track real time when this fever started so we can freeze the game clock
	var current_real_sec: float = (Time.get_ticks_msec() - _start_ticks) / 1000.0
	_fever_start_real_sec = current_real_sec
	
	# Clear all active notes so the screen is clean for the fever door
	_clear_active_notes()
	# Rewind spawn index so notes after frozen time can re-spawn after fever ends
	var frozen_t: float = now_sec()
	_spawn_index = _chart_notes.size() # DEFAULT TO END
	for i in range(_chart_notes.size()):
		var note_t: float = float(_chart_notes[i].get("t", 0.0))
		if note_t - _approach_time > frozen_t:
			_spawn_index = i
			break
	
	_fever_end_time = now_sec() + FEVER_DURATION
	_fever_scratch_count = 0
	_fever_door_opened = false
	_fever_count += 1
	gauge_changed.emit(gauge)
	fever_started.emit()

func _update_fever(t: float) -> void:
	if is_fever:
		var current_real_sec: float = (Time.get_ticks_msec() - _start_ticks) / 1000.0
		var elapsed_fever: float = current_real_sec - _fever_start_real_sec
		if elapsed_fever >= FEVER_DURATION:
			# Ensure time is unfrozen if not already done by door opening
			_unfreeze_fever_time()
			is_fever = false
			fever_ended.emit()
			if DEBUG_FEVER_RESUME:
				print("[DEBUG FEVER] Fever expired at t=" + str(t) + ". Resetting state.")


func get_score_multiplier() -> float:
	return FEVER_MULTIPLIER if is_fever else 1.0

## ---- Score + Combo (TICKET 10-3) ----

func _update_score(grade: int) -> void:
	if grade == Judgement.Grade.MISS:
		combo = 0
	else:
		combo += 1
	var weight: float = SCORE_WEIGHT.get(grade, 0.0)
	var combo_mult: float = 1.0 + minf(float(combo), 100.0) * 0.005
	var fever_mult: float = get_score_multiplier()
	var gain: int = int(roundf(float(BASE_SCORE) * weight * combo_mult * fever_mult))
	score += gain
	score_changed.emit(score, combo)
