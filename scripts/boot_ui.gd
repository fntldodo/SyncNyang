extends Control
@onready var start_btn: Button = $"Center/StartButton"

func _ready() -> void:
	start_btn.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	SceneRouter.flow_to_game()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
