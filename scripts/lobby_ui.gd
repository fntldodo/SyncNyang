extends Control

const SafeArea := preload("res://scripts/safe_area.gd")

@onready var play_btn: Button = $"Center/PlayBtn"
@onready var wardrobe_btn: Button = $"Center/WardrobeBtn"
@onready var back_btn: Button = $"Center/BackBtn"

func _ready() -> void:
	play_btn.pressed.connect(_on_play)
	wardrobe_btn.pressed.connect(_on_wardrobe)
	back_btn.pressed.connect(_on_back)
	_apply_safe_area()

func _apply_safe_area() -> void:
	var insets: Dictionary = SafeArea.get_insets()
	var center: Control = $"Center"
	center.offset_top += insets["top"] * 0.3
	center.offset_bottom -= insets["bottom"] * 0.3

func _on_play() -> void:
	SceneRouter.flow_to_game()

func _on_wardrobe() -> void:
	SceneRouter.flow_to_wardrobe()

func _on_back() -> void:
	SceneRouter.clear_to_boot()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.clear_to_boot()
