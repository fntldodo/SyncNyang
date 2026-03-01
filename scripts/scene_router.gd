extends Node

const SCENE_BOOT := "res://scenes/Boot.tscn"
const SCENE_CUTSCENE := "res://scenes/Cutscene.tscn"
const SCENE_GAME := "res://scenes/Game.tscn"
const SCENE_RESULT := "res://scenes/Result.tscn"
const SCENE_WARDROBE := "res://scenes/Wardrobe.tscn"

var _stack: Array[String] = []
var _is_changing := false

func _ready() -> void:
	if get_tree().current_scene == null:
		goto(SCENE_BOOT, true)

func goto(path: String, reset_stack: bool = false) -> void:
	if _is_changing:
		return
	_is_changing = true

	if reset_stack:
		_stack.clear()
	else:
		var cur := get_tree().current_scene
		if cur and cur.scene_file_path != "":
			_stack.append(cur.scene_file_path)

	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter.goto failed: %s (err=%s)" % [path, str(err)])

	_is_changing = false

func replace(path: String) -> void:
	if _is_changing:
		return
	_is_changing = true

	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter.replace failed: %s (err=%s)" % [path, str(err)])

	_is_changing = false

func back() -> void:
	if _is_changing:
		return
	if _stack.is_empty():
		goto(SCENE_BOOT, true)
		return

	_is_changing = true
	var prev: String = _stack.pop_back()
	var err := get_tree().change_scene_to_file(prev)
	if err != OK:
		push_error("SceneRouter.back failed: %s (err=%s)" % [prev, str(err)])
	_is_changing = false

func clear_to_boot() -> void:
	goto(SCENE_BOOT, true)

func flow_to_cutscene() -> void:
	goto(SCENE_CUTSCENE)

func flow_to_game() -> void:
	goto(SCENE_GAME)

func flow_to_result() -> void:
	goto(SCENE_RESULT)

func flow_to_wardrobe() -> void:
	goto(SCENE_WARDROBE)

func handle_global_back_action() -> void:
	back()
