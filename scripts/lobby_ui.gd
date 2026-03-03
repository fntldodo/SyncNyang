extends Control

@onready var play_btn: Button = $"Center/PlayBtn"
@onready var wardrobe_btn: Button = $"Center/WardrobeBtn"
@onready var back_btn: Button = $"Center/BackBtn"

func _ready() -> void:
	play_btn.pressed.connect(_on_play)
	wardrobe_btn.pressed.connect(_on_wardrobe)
	back_btn.pressed.connect(_on_back)

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
