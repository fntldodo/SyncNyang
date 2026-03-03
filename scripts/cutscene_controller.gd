extends Control

## Cutscene Controller — 6-image sequential viewer, no text.
## Tap to advance, BACK to Boot, SKIP to Game, 0.25s fade transitions.

const CUTS: Array[String] = [
	"res://assets/story/cutscene_01_happy_time.png",
	"res://assets/story/cutscene_02_ufo_appears.png",
	"res://assets/story/cutscene_03_beam_invites_owner.png",
	"res://assets/story/cutscene_04_cat_determined.png",
	"res://assets/story/cutscene_05_can_stairs_climb.png",
	"res://assets/story/cutscene_06_alien_dog_stage.png",
]

## Pastel placeholder colors when image is missing
const PLACEHOLDERS: Array[Color] = [
	Color(0.95, 0.85, 0.78),  # warm peach
	Color(0.80, 0.88, 0.95),  # sky blue
	Color(0.85, 0.78, 0.95),  # lavender
	Color(0.78, 0.95, 0.82),  # mint
	Color(0.95, 0.92, 0.78),  # cream yellow
	Color(0.95, 0.78, 0.85),  # rose pink
]

@onready var image_rect: TextureRect = $ImageRect
@onready var placeholder_bg: ColorRect = $PlaceholderBG
@onready var back_btn: Button = $TopOverlay/BackBtn
@onready var skip_btn: Button = $TopOverlay/SkipBtn
@onready var tap_area: Panel = $TapArea

var _index: int = 0
var _transitioning: bool = false

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	skip_btn.pressed.connect(_on_skip)
	tap_area.gui_input.connect(_on_tap_input)
	_show_cut(0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

func _on_tap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_next()
	elif event is InputEventScreenTouch and event.pressed:
		_next()

func _next() -> void:
	if _transitioning:
		return
	_index += 1
	if _index >= CUTS.size():
		SceneRouter.flow_to_lobby()
		return
	_fade_to(_index)

func _on_back() -> void:
	if _transitioning:
		return
	SceneRouter.clear_to_boot()

func _on_skip() -> void:
	if _transitioning:
		return
	SceneRouter.flow_to_lobby()

func _show_cut(idx: int) -> void:
	var path: String = CUTS[idx]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex:
		image_rect.texture = tex
		image_rect.visible = true
		placeholder_bg.visible = false
	else:
		image_rect.visible = false
		placeholder_bg.visible = true
		var col_idx: int = idx % PLACEHOLDERS.size()
		placeholder_bg.color = PLACEHOLDERS[col_idx]

func _fade_to(idx: int) -> void:
	_transitioning = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(_show_cut.bind(idx))
	tw.tween_property(self, "modulate:a", 1.0, 0.13)
	tw.tween_callback(_on_fade_done)

func _on_fade_done() -> void:
	_transitioning = false
