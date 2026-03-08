extends Control

const SafeArea := preload("res://scripts/safe_area.gd")

@onready var bg: TextureRect = $"BackgroundLayer/BG"
@onready var logo_image: TextureRect = $"TitleLayer/LogoImage"
@onready var logo_pill: Panel = $"TitleLayer/LogoPill"
@onready var logo_text: Label = $"TitleLayer/LogoText"

@onready var start_btn: Button = $"BottomUILayer/BottomGlass/Center/StartButton"
@onready var easy_btn: Button = $"BottomUILayer/BottomGlass/Center/DiffRow/EasyBtn"
@onready var normal_btn: Button = $"BottomUILayer/BottomGlass/Center/DiffRow/NormalBtn"
@onready var hard_btn: Button = $"BottomUILayer/BottomGlass/Center/DiffRow/HardBtn"

var _selected_diff: String = "normal"

## Accent color for selected button
const ACCENT_COLOR := Color(1.0, 0.72, 0.42, 1.0)  # #FFB86B pastel orange
const DEFAULT_COLOR := Color(0.42, 0.42, 0.47, 1.0)  # grey

func _ready() -> void:
	# TICKET 12-1: Logo fallback logic
	var logo_path := "res://assets/logo_title.png"
	if ResourceLoader.exists(logo_path):
		var tex := load(logo_path) as Texture2D
		if tex != null:
			logo_image.texture = tex
			logo_image.visible = true
			logo_pill.visible = false
			logo_text.visible = false
		else:
			_show_fallback_logo()
	else:
		_show_fallback_logo()

	start_btn.pressed.connect(_on_start_pressed)
	easy_btn.pressed.connect(_select_diff.bind("easy"))
	normal_btn.pressed.connect(_select_diff.bind("normal"))
	hard_btn.pressed.connect(_select_diff.bind("hard"))
	_update_diff_buttons()
	_apply_safe_area()

func _show_fallback_logo() -> void:
	logo_image.visible = false
	logo_pill.visible = true
	logo_text.visible = true

func _apply_safe_area() -> void:
	var insets: Dictionary = SafeArea.get_insets()
	# Push bottom glass panel up by safe bottom inset
	var glass: Panel = $"BottomUILayer/BottomGlass"
	glass.offset_bottom -= insets["bottom"]
	glass.offset_top -= insets["bottom"]

func _select_diff(diff: String) -> void:
	_selected_diff = diff
	_update_diff_buttons()

func _update_diff_buttons() -> void:
	var btns: Array = [
		{"btn": easy_btn, "diff": "easy"},
		{"btn": normal_btn, "diff": "normal"},
		{"btn": hard_btn, "diff": "hard"},
	]
	for entry in btns:
		var btn: Button = entry["btn"]
		var style: StyleBoxFlat = btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		if entry["diff"] == _selected_diff:
			style.bg_color = ACCENT_COLOR
		else:
			style.bg_color = DEFAULT_COLOR
		btn.add_theme_stylebox_override("normal", style)

func _on_start_pressed() -> void:
	SceneRouter.selected_difficulty = _selected_diff
	SceneRouter.flow_to_cutscene()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
