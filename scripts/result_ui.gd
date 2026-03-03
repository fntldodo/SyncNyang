extends Control

const RewardSystem := preload("res://scripts/reward_system.gd")

## TICKET 1 — existing buttons
@onready var retry_btn: Button = $"Panel/BtnRow/RetryBtn"
@onready var wardrobe_btn: Button = $"Panel/BtnRow/WardrobeBtn"
@onready var back_btn: Button = $"Panel/BackBtn"

## TICKET 5 — reward UI
@onready var rank_label: Label = $"Panel/RankLabel"
@onready var stats_label: Label = $"Panel/StatsLabel"
@onready var claim_btn: Button = $"Panel/ClaimBtn"
@onready var reward_label: Label = $"Panel/RewardLabel"
@onready var score_label: Label = $"Panel/ScoreLabel"

var _reward_system: RefCounted = null
var _claimed: bool = false

func _ready() -> void:
	retry_btn.pressed.connect(_on_retry)
	wardrobe_btn.pressed.connect(_on_wardrobe)
	back_btn.pressed.connect(_on_back)
	claim_btn.pressed.connect(_on_claim)

	_reward_system = RewardSystem.new()
	reward_label.text = ""

	_display_summary()

func _display_summary() -> void:
	var s: Dictionary = SaveData.last_run_summary
	if s.is_empty():
		rank_label.text = "RANK: -"
		stats_label.text = "Play a game first!"
		claim_btn.disabled = true
		return

	rank_label.text = "RANK: %s" % s.get("rank", "?")
	stats_label.text = "P:%d  E:%d  G:%d  S:%d  M:%d" % [
		s.get("perfect", 0), s.get("excellent", 0),
		s.get("good", 0), s.get("soso", 0), s.get("miss", 0)
	]
	score_label.text = "Score: %d" % s.get("score", 0)

func _on_claim() -> void:
	if _claimed:
		return
	_claimed = true
	claim_btn.disabled = true

	var s: Dictionary = SaveData.last_run_summary
	if s.is_empty():
		reward_label.text = "No run data!"
		return

	var result: Dictionary = _reward_system.grant_clear_reward(s, SaveData)
	var rarity_tag: String = result.get("item_rarity", "common").to_upper()
	var bonus_pp: float = result.get("bonus_pp", 0.0)
	var bonus_tag: String = ""
	if bonus_pp > 0.001:
		bonus_tag = "  (Luck +%d%%)" % int(roundf(bonus_pp * 100.0))
	reward_label.text = "+%d coins  |  [%s] %s%s" % [
		result.get("coins", 0),
		rarity_tag,
		result.get("item_name", "???"),
		bonus_tag
	]

func _on_retry() -> void:
	SceneRouter.replace(SceneRouter.SCENE_GAME)

func _on_wardrobe() -> void:
	SceneRouter.flow_to_wardrobe()

func _on_back() -> void:
	SceneRouter.flow_to_lobby()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.handle_global_back_action()
