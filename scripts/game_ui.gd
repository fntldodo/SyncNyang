extends Control

const Judgement := preload("res://scripts/judgement.gd")

## TICKET 1 — existing TopBar buttons
@onready var back_btn: Button = $"TopBar/BackBtn"
@onready var next_btn: Button = $"TopBar/NextBtn"

## TICKET 2 — judgement nodes
@onready var hit_line: ColorRect = $"HitLine"
@onready var note_rect: ColorRect = $"Note"
@onready var judge_label: Label = $"JudgeLabel"
@onready var game_controller: Node = $"GameController"

## Note spawn Y (top area, will slide down to HitLine)
var _note_spawn_y: float = 200.0
var _judge_tween: Tween = null

func _ready() -> void:
	# TICKET 1 — button wiring
	back_btn.pressed.connect(_on_back)
	next_btn.pressed.connect(_on_next)

	# TICKET 2 — start the dummy note run
	game_controller.judgement_emitted.connect(_on_judgement)
	game_controller.start_run()

	# Reset judge label
	judge_label.modulate.a = 0.0

func _process(_delta: float) -> void:
	# TICKET 2 — move note each frame
	game_controller.update_dummy_note(note_rect, hit_line, _note_spawn_y)

## ---- TICKET 1 callbacks (unchanged) ----

func _on_back() -> void:
	SceneRouter.back()

func _on_next() -> void:
	SceneRouter.flow_to_result()

## ---- Input handling ----

func _unhandled_input(event: InputEvent) -> void:
	# TICKET 1 — Android back / Escape
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.handle_global_back_action()
		return

	# TICKET 2 — Tap detection (touch + mouse for desktop testing)
	if _is_tap_event(event):
		get_viewport().set_input_as_handled()
		game_controller.handle_tap()

func _is_tap_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and event.pressed:
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	return false

## ---- TICKET 2: Judgement display ----

func _on_judgement(grade: int, _delta_ms: float) -> void:
	_show_judge(grade)
	# Hide note on any judgement (including MISS)
	note_rect.visible = false

func _show_judge(grade: int) -> void:
	# Cancel any running tween
	if _judge_tween and _judge_tween.is_valid():
		_judge_tween.kill()

	# Set text and color
	judge_label.text = Judgement.get_grade_name(grade)
	judge_label.modulate = Judgement.get_color(grade)
	judge_label.modulate.a = 1.0

	# Tween: visible 0.25s -> fade out 0.15s (total ~0.4s)
	_judge_tween = create_tween()
	_judge_tween.tween_interval(0.25)
	_judge_tween.tween_property(judge_label, "modulate:a", 0.0, 0.15)
