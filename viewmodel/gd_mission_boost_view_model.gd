class_name MissionBoostViewModel
extends ViewModel
## VIEWMODEL: one rung of the Ruins boost ladder - what it currently contributes,
## what one more level adds, and what that costs.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One per authored rung, built once and owned by App: every card repaints on any
## mission-currency change, so they all need live state at the same time.

const PROP_BOOST_CHANGED := &"boost_changed"

var _id: StringName
var _def: MissionBoostDef

# --- View -> ViewModel ---

func buy() -> void:
	App.buy_mission_boost(_id)

# --- Read-only display properties bound by the View ---

var display_name: String:
	get: return _def.display_name

var description: String:
	get: return EffectLabel.expand(_def.description, _def.effects, _def.max_level)

## Which half of the ladder this rung sits in. Read off the stats its effects
## name rather than an authored flag, so a rung cannot claim to be one and behave
## as the other.
var is_general: bool:
	get:
		for effect in _def.effects:
			if not RuinsViewModel.CONTROL_STATS.has(effect.stat):
				return true
		return false

var level_text: String:
	get:
		var ceiling := App.mission_boost_max_level(_id)
		if ceiling <= 0:
			return "Lv %d" % App.mission_boost_level(_id)
		return "Lv %d / %d" % [App.mission_boost_level(_id), ceiling]

var bonus_text: String:
	get:
		if App.mission_boost_level(_id) <= 0:
			return "-"
		return _effect_text(App.mission_boost_amount(_id))

var next_level_text: String:
	get:
		if is_maxed:
			return ""
		return "next %s" % _effect_text(App.mission_boost_next_level_delta(_id))

var cost_text: String:
	get:
		if not is_unlocked:
			return "Opens after %d more missions" % App.missions_until_boost_unlock(_id)
		if is_maxed:
			return "-"
		return "%s %s" % [App.mission_boost_cost(_id).to_display(), _currency_name]

var is_maxed: bool:
	get: return App.is_mission_boost_maxed(_id)

var is_unlocked: bool:
	get: return App.is_mission_boost_unlocked(_id)

var can_buy: bool:
	get: return App.can_buy_mission_boost(_id)

# --- Lifecycle ---

func _init(boost_id: StringName, def: MissionBoostDef) -> void:
	_id = boost_id
	_def = def
	App.mission_upgrade_system.upgrades_changed.connect(_on_changed)
	App.ruins_data.missions_completed_changed.connect(_on_changed.unbind(1))
	App.player_data.relics_changed.connect(_on_balance_changed)
	App.player_data.ichor_changed.connect(_on_balance_changed)
	App.player_data.glyphs_changed.connect(_on_balance_changed)

func dispose() -> void:
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.ruins_data.missions_completed_changed.disconnect(_on_changed.unbind(1))
	App.player_data.relics_changed.disconnect(_on_balance_changed)
	App.player_data.ichor_changed.disconnect(_on_balance_changed)
	App.player_data.glyphs_changed.disconnect(_on_balance_changed)

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_BOOST_CHANGED)

func _on_balance_changed(_value: BigNumber) -> void:
	_notify(PROP_BOOST_CHANGED)

# --- Formatting ---

var _currency_name: String:
	get:
		if _def.currency == null:
			return "relics"
		return _def.currency.currency_name.to_lower()

## An ADD rung reads as a signed amount and everything else as a multiplier: a
## slot is "+1", not "x1". Read off the first effect's op, since a rung writing
## two stats with different ops would have no single honest caption anyway.
func _effect_text(amount: BigNumber) -> String:
	if _def.effects.is_empty():
		return "-"
	if _def.effects[0].op == UpgradeEffectDef.Op.ADD:
		var value := amount.to_float()
		return "%+.2f" % value if absf(value) < 10.0 else "%+d" % int(value)
	return "x%s" % amount.add(BigNumber.from_value(1.0)).to_display(2)
