extends RefCounted

## RewardSystem — grants coins + random item based on run rank.

const ItemsDB := preload("res://scripts/items_db.gd")

const BASE_COINS := 50
const RANK_BONUS: Dictionary = {
	"S": 50, "A": 30, "B": 15, "C": 5, "D": 0,
}

var _items_db: RefCounted = null
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_items_db = ItemsDB.new()
	_rng.randomize()

## Main entry: grant reward and return summary dict.
## summary: { "rank": "A", "perfect": 5, ... }
## save: SaveData autoload reference
func grant_clear_reward(summary: Dictionary, save: Node) -> Dictionary:
	var rank: String = summary.get("rank", "D")

	# Coins
	var coin_reward: int = BASE_COINS + RANK_BONUS.get(rank, 0)
	save.add_coins(coin_reward)

	# Pick 1 random item by rarity weights
	var rarity: String = _pick_rarity(rank)
	var item: Dictionary = _pick_random_item(rarity)
	var item_id: String = item.get("id", "")
	var item_name: String = item.get("name", "???")

	if item_id != "":
		save.add_item(item_id)

	return {
		"coins": coin_reward,
		"item_id": item_id,
		"item_name": item_name,
		"item_rarity": rarity,
		"rank": rank,
	}

## Pick rarity based on rank weights.
func _pick_rarity(rank: String) -> String:
	var weights: Dictionary = _items_db.get_rarity_weights(rank)
	var common_w: int = int(weights.get("common", 100))
	var rare_w: int = int(weights.get("rare", 0))
	var epic_w: int = int(weights.get("epic", 0))

	var total: int = common_w + rare_w + epic_w
	var roll: int = _rng.randi_range(1, total)

	if roll <= common_w:
		return "common"
	elif roll <= common_w + rare_w:
		return "rare"
	else:
		return "epic"

## Pick a random item of the given rarity.
func _pick_random_item(rarity: String) -> Dictionary:
	var pool: Array = _items_db.get_items_by_rarity(rarity)
	if pool.is_empty():
		# Fallback to common
		pool = _items_db.get_items_by_rarity("common")
	if pool.is_empty():
		return {}
	var idx: int = _rng.randi_range(0, pool.size() - 1)
	return pool[idx]
