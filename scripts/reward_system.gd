extends RefCounted

## RewardSystem — grants coins + random item based on run rank.
## TICKET 10-4: fever + rank rarity bonus (capped 4%p, rare max 15%).

const ItemsDB := preload("res://scripts/items_db.gd")

const BASE_COINS := 50
const RANK_BONUS: Dictionary = {
	"S": 50, "A": 30, "B": 15, "C": 5, "D": 0,
}

## Rarity bonus caps (TICKET 10-4)
const FEVER_BONUS_PP := 0.02   # +2%p if fever triggered ≥1
const RANK_BONUS_PP := 0.02    # +2%p if rank S or A
const TOTAL_BONUS_CAP := 0.04  # max 4%p total
const RARE_CHANCE_CAP := 0.15  # rare can never exceed 15%

var _items_db: RefCounted = null
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_items_db = ItemsDB.new()
	_rng.randomize()

## Main entry: grant reward and return summary dict.
## summary: { "rank": "A", "perfect": 5, ..., "fever_count": 1 }
## save: SaveData autoload reference
func grant_clear_reward(summary: Dictionary, save: Node) -> Dictionary:
	var rank: String = summary.get("rank", "D")

	# Coins
	var coin_reward: int = BASE_COINS + RANK_BONUS.get(rank, 0)
	save.add_coins(coin_reward)

	# Compute rarity bonus (TICKET 10-4)
	var fever_count: int = int(summary.get("fever_count", 0))
	var fever_pp: float = FEVER_BONUS_PP if fever_count >= 1 else 0.0
	var rank_pp: float = RANK_BONUS_PP if rank in ["S", "A"] else 0.0
	var bonus_pp: float = minf(fever_pp + rank_pp, TOTAL_BONUS_CAP)

	# Pick 1 random item by rarity weights + bonus
	var rarity: String = _pick_rarity(rank, bonus_pp)
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
		"bonus_pp": bonus_pp,
	}

## Pick rarity based on rank weights + bonus percentage points.
func _pick_rarity(rank: String, bonus_pp: float) -> String:
	var weights: Dictionary = _items_db.get_rarity_weights(rank)
	var common_w: int = int(weights.get("common", 100))
	var rare_w: int = int(weights.get("rare", 0))
	var epic_w: int = int(weights.get("epic", 0))

	var total: int = common_w + rare_w + epic_w
	if total <= 0:
		return "common"

	# Apply bonus to rare chance, capped
	var base_rare_pct: float = float(rare_w) / float(total)
	var boosted_rare_pct: float = minf(base_rare_pct + bonus_pp, RARE_CHANCE_CAP)

	# Convert back to weights (scale to 1000 for precision)
	var scale: int = 1000
	var epic_pct: float = float(epic_w) / float(total)
	var new_rare_w: int = int(roundf(boosted_rare_pct * float(scale)))
	var new_epic_w: int = int(roundf(epic_pct * float(scale)))
	var new_common_w: int = scale - new_rare_w - new_epic_w

	var roll: int = _rng.randi_range(1, scale)
	if roll <= new_common_w:
		return "common"
	elif roll <= new_common_w + new_rare_w:
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
