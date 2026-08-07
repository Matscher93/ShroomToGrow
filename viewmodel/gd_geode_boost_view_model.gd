class_name GeodeBoostViewModel
extends ViewModel
## VIEWMODEL: one geode boost's card - its level on the ladder, what tier the
## next level lands in, and what that costs.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One per authored boost, built once and owned by App: every card repaints on
## any crystal change, so they all need live state at the same time.

const PROP_BOOST_CHANGED := &"boost_changed"

var _id: StringName
var _def: GeodeBoostDef

# --- View -> ViewModel ---

func buy() -> void:
	App.buy_geode_boost(_id)

# --- Read-only display properties bound by the View ---

var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

var level_text: String:
	get: return "Lv %d / %d" % [App.geode_boost_level(_id), GeodeTiers.max_level()]

## The tier the next level lands in and how far into it the ladder already is -
## the two numbers that explain both the price jump and the rate jump at a
## boundary.
var tier_text: String:
	get:
		if is_maxed:
			return "Maxed"
		var tier := App.geode_boost_tier(_id)
		var within := App.geode_boost_level(_id) % GeodeTiers.LEVELS_PER_TIER
		return "Tier %d - %d / %d" % [tier, within, GeodeTiers.LEVELS_PER_TIER]

## Shown as a multiplier rather than a percentage: the levels compound, so a
## maxed ladder is several trillion times over and "+500000000000%" is not a
## number anyone reads.
var bonus_text: String:
	get: return "x%s" % App.geode_boost_multiplier(_id).to_display(2)

var next_level_text: String:
	get:
		if is_maxed:
			return ""
		return "next x%.2f" % (1.0 + App.geode_boost_next_gain(_id))

## Both numbers, because both are true: the price is authored in geodes, and
## crystals are what the purchase actually takes out of the player's pocket.
var cost_text: String:
	get:
		if is_maxed:
			return "-"
		return "%s geodes (%s crystals)" % [
			App.geode_boost_cost(_id).to_display(),
			App.geode_boost_crystal_cost(_id).to_display()]

var is_maxed: bool:
	get: return App.is_geode_boost_maxed(_id)

var can_buy: bool:
	get: return App.can_buy_geode_boost(_id)

# --- Lifecycle ---

func _init(boost_id: StringName, def: GeodeBoostDef) -> void:
	_id = boost_id
	_def = def
	App.player_data.crystals_changed.connect(_on_crystals_changed)
	App.geode_upgrade_system.upgrades_changed.connect(_on_changed)

func dispose() -> void:
	App.player_data.crystals_changed.disconnect(_on_crystals_changed)
	App.geode_upgrade_system.upgrades_changed.disconnect(_on_changed)

# --- Model -> notification plumbing ---

func _on_crystals_changed(_value: BigNumber) -> void:
	_notify(PROP_BOOST_CHANGED)

func _on_changed() -> void:
	_notify(PROP_BOOST_CHANGED)
