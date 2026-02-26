extends Control
@onready var retry_btn: Button = $"Panel/BtnRow/RetryBtn"
@onready var wardrobe_btn: Button = $"Panel/BtnRow/WardrobeBtn"
@onready var back_btn: Button = $"Panel/BackBtn"

func _ready() -> void:
	retry_btn.pressed.connect(_on_retry)
	wardrobe_btn.pressed.connect(_on_wardrobe)
	back_btn.pressed.connect(_on_back)

func _on_retry() -> void:
	SceneRouter.replace(SceneRouter.SCENE_GAME)

func _on_wardrobe() -> void:
	SceneRouter.flow_to_wardrobe()

func _on_back() -> void:
	SceneRouter.back()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.handle_global_back_action()
