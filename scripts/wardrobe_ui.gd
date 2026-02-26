extends Control
@onready var back_btn: Button = $"Panel/BackBtn"

func _ready() -> void:
	back_btn.pressed.connect(_on_back)

func _on_back() -> void:
	SceneRouter.back()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.handle_global_back_action()
