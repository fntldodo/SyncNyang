extends Control

## Game UI — input wiring, lane detection, difficulty selector.
## TICKET 8: hold&drag lane tracking for moving notes + cursor indicator.

const Judgement := preload("res://scripts/judgement.gd")

## TopBar
@onready var back_btn: Button = $"TopBar/BackBtn"
@onready var next_btn: Button = $"TopBar/NextBtn"
@onready var diff_row: HBoxContainer = $"TopBar/DiffRow"

## Game elements
@onready var hit_line: ColorRect = $"HitLine"
@onready var judge_label: Label = $"JudgeLabel"
@onready var game_controller: Node = $"GameController"
@onready var tap_area: Panel = $"TapArea"
@onready var fx_layer: Node = $"FxLayer"
@onready var notes_layer: Control = $"NotesLayer"
@onready var cursor_indicator: ColorRect = $"CursorIndicator"

## Lane geometry
const NUM_LANES := 3
var _lane_centers: Array = []
var _lane_width: float = 0.0
var _scratch_threshold_y: float = 40.0

## State
var _note_spawn_y: float = 200.0
var _judge_tween: Tween = null
var _current_diff: String = "normal"
var _last_action: String = "tap"

## Touch tracking (tap/scratch)
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_active: bool = false

## Hold & drag lane tracking (moving notes)
var _held_lane: int = 1
var _holding: bool = false

## Debug keyboard
const DEBUG_KEYS := true
const COMBO_WINDOW_MS := 120.0
var _last_key: int = -1
var _last_key_time_ms: float = 0.0

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	next_btn.pressed.connect(_on_next)
	game_controller.judgement_emitted.connect(_on_judgement)
	game_controller.run_finished.connect(_on_run_finished)
	tap_area.gui_input.connect(_on_tap_area_input)
	judge_label.modulate.a = 0.0

	_compute_lane_geometry()
	_setup_diff_buttons()
	_setup_controller()
	_update_cursor_visual()
	_start_chart(_current_diff)

func _process(_delta: float) -> void:
	# Sync cursor lane to controller
	game_controller.cursor_lane = _held_lane
	game_controller.process_update()
	_update_cursor_visual()

## ---- Lane geometry ----

func _compute_lane_geometry() -> void:
	var vw: float = get_viewport().get_visible_rect().size.x
	_lane_width = vw / float(NUM_LANES)
	_lane_centers.clear()
	for i in range(NUM_LANES):
		_lane_centers.append(_lane_width * (float(i) + 0.5))
	_scratch_threshold_y = vw * 0.06

func _get_lane_from_x(x: float) -> int:
	if _lane_width <= 0:
		return 1
	return clampi(int(x / _lane_width), 0, NUM_LANES - 1)

func _get_scratch_pair_from_x(x: float) -> int:
	var mid: float = _lane_centers[1] if _lane_centers.size() > 1 else 540.0
	return 0 if x < mid else 1

## ---- Cursor visual ----

func _update_cursor_visual() -> void:
	if not cursor_indicator or _lane_centers.is_empty():
		return
	var cx: float = _lane_centers[_held_lane] if _held_lane < _lane_centers.size() else 540.0
	var indicator_w: float = 80.0
	cursor_indicator.position.x = cx - indicator_w * 0.5
	cursor_indicator.size.x = indicator_w
	cursor_indicator.modulate.a = 0.7 if _holding else 0.35

## ---- Controller setup ----

func _setup_controller() -> void:
	game_controller.notes_layer = notes_layer
	game_controller.spawn_y = _note_spawn_y
	game_controller.hitline_y = hit_line.position.y
	game_controller.lane_centers_x = _lane_centers

## ---- Difficulty ----

func _setup_diff_buttons() -> void:
	var diffs: Array = ["easy", "normal", "hard"]
	var labels: Array = ["EASY", "NORMAL", "HARD"]
	for i in range(diffs.size()):
		var btn := Button.new()
		btn.text = labels[i]
		btn.pressed.connect(_on_diff_selected.bind(diffs[i]))
		diff_row.add_child(btn)

func _on_diff_selected(diff: String) -> void:
	_current_diff = diff
	game_controller.stop_run()
	_start_chart(diff)

func _start_chart(diff: String) -> void:
	game_controller.start_run(diff)

## ---- Navigation ----

func _on_back() -> void:
	game_controller.stop_run()
	SceneRouter.back()

func _on_next() -> void:
	SaveData.last_run_summary = game_controller.get_run_summary()
	game_controller.stop_run()
	SceneRouter.flow_to_result()

func _on_run_finished() -> void:
	SaveData.last_run_summary = game_controller.get_run_summary()
	SceneRouter.flow_to_result()

## ---- Input ----

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		game_controller.stop_run()
		SceneRouter.handle_global_back_action()
		return
	# Debug keyboard (editor only)
	if DEBUG_KEYS and OS.has_feature("editor") and event is InputEventKey and event.pressed and not event.echo:
		_handle_debug_key(event.keycode)

func _on_tap_area_input(event: InputEvent) -> void:
	# Touch events
	if event is InputEventScreenTouch:
		_handle_touch(event.position, event.pressed)
		return
	if event is InputEventScreenDrag:
		_update_held_lane_from_x(event.position.x)
		return
	# Mouse events (editor testing)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(event.position, event.pressed)
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_update_held_lane_from_x(event.position.x)
		return

func _handle_touch(pos: Vector2, pressed: bool) -> void:
	if pressed:
		_touch_start_pos = pos
		_touch_active = true
		_holding = true
		_update_held_lane_from_x(pos.x)
	else:
		_holding = false
		if not _touch_active:
			return
		_touch_active = false
		tap_area.accept_event()
		_classify_and_dispatch(pos)

func _update_held_lane_from_x(x: float) -> void:
	_held_lane = _get_lane_from_x(x)
	_holding = true

func _classify_and_dispatch(end_pos: Vector2) -> void:
	var dx: float = end_pos.x - _touch_start_pos.x
	var dy: float = end_pos.y - _touch_start_pos.y
	if absf(dy) > absf(dx) and absf(dy) >= _scratch_threshold_y:
		_last_action = "scratch"
		game_controller.handle_scratch(_get_scratch_pair_from_x(_touch_start_pos.x))
	else:
		_last_action = "tap"
		game_controller.handle_tap(_get_lane_from_x(_touch_start_pos.x))

## ---- Judgement display + FX ----

func _on_judgement(grade: int, delta_ms: float) -> void:
	_show_judge(grade, delta_ms)
	_spawn_pawprint_fx(grade)

func _show_judge(grade: int, delta_ms: float = 0.0) -> void:
	if _judge_tween and _judge_tween.is_valid():
		_judge_tween.kill()
	var ms_text: String = "%dms" % int(absf(delta_ms))
	judge_label.text = "%s (%s)" % [Judgement.get_grade_name(grade), ms_text]
	judge_label.modulate = Judgement.get_color(grade)
	judge_label.modulate.a = 1.0
	_judge_tween = create_tween()
	_judge_tween.tween_interval(0.25)
	_judge_tween.tween_property(judge_label, "modulate:a", 0.0, 0.15)

func _spawn_pawprint_fx(grade: int) -> void:
	var tint: Color = Judgement.get_color(grade)
	var spawn_pos: Vector2 = hit_line.global_position + Vector2(30.0, -30.0)
	var is_scratch: bool = (_last_action == "scratch")
	fx_layer.spawn_pawprint(spawn_pos, tint, is_scratch, 0)

## ---- Debug keyboard: QWE tap/scratch + arrow lane move (editor only) ----

func _handle_debug_key(keycode: int) -> void:
	# Arrow keys: move held lane for moving notes
	if keycode == KEY_LEFT:
		_held_lane = clampi(_held_lane - 1, 0, NUM_LANES - 1)
		return
	if keycode == KEY_RIGHT:
		_held_lane = clampi(_held_lane + 1, 0, NUM_LANES - 1)
		return

	# QWE: tap/scratch
	if keycode != KEY_Q and keycode != KEY_W and keycode != KEY_E:
		return
	var now_ms: float = float(Time.get_ticks_msec())
	var lane: int = _key_to_lane(keycode)
	var _grade: int = -1
	# Check scratch combo
	if _last_key >= 0 and (now_ms - _last_key_time_ms) <= COMBO_WINDOW_MS:
		var pair: int = _try_scratch_pair(_last_key, keycode)
		if pair >= 0:
			_last_action = "scratch"
			_grade = game_controller.handle_scratch(pair)
			_last_key = -1
			return
	# Immediate TAP
	_last_action = "tap"
	_grade = game_controller.handle_tap(lane)
	_last_key = keycode
	_last_key_time_ms = now_ms

func _try_scratch_pair(first: int, second: int) -> int:
	if (first == KEY_Q and second == KEY_W) or (first == KEY_W and second == KEY_Q):
		return 0
	if (first == KEY_W and second == KEY_E) or (first == KEY_E and second == KEY_W):
		return 1
	return -1

func _key_to_lane(keycode: int) -> int:
	match keycode:
		KEY_Q: return 0
		KEY_W: return 1
		KEY_E: return 2
	return 1
