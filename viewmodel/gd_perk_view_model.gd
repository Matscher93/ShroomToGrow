class_name PerkViewModel
extends ViewModel
## VIEWMODEL — adapts one PerkDef + the shared prestige upgrade system for
## display. One instance per perk, held in App.perk_vms. Holds references to
## the model; never to any Node.

const PROP_CHANGED := &"changed"

var _id: StringName
var _def: PerkDef

# --- Static display properties (fixed for this perk's lifetime) ---
var display_name: String:
	get: return _def.display_name

var max_level: int:
	get: return _def.max_level

# --- Read-only display properties the View binds to ---
var status: String:
	get: return App.perk_status(_id)

var level: int:
	get: return App.prestige_upgrade_system.level(_id)

var owned: bool:
	get: return level > 0

var tooltip_text: String:
	get: return "%s — Lv %d/%d" % [_def.display_name, level, max_level]

var detail_effect_text: String:
	get:
		if _def.effects.is_empty():
			return _def.description
		var effect := _def.effects[0]
		if effect.op == UpgradeEffectDef.Op.ADD:
			return "%+.1f %s per level" % [effect.per_level, effect.stat]
		return "%+.0f%% %s per level" % [effect.per_level * 100.0, effect.stat]

var detail_cost_text: String:
	get:
		if status == "locked":
			return "Locked — unlock its parent first"
		if level >= max_level:
			return "Maxed"
		return "Cost: %s biomass" % App.prestige_upgrade_system.cost(_id)._to_string()

var detail_buy_text: String:
	get:
		if status == "locked":
			return "Locked"
		if level >= max_level:
			return "Maxed"
		return "Buy"

var can_buy: bool:
	get: return App.can_buy_perk(_id)

# --- Lifecycle ---

func _init(id: StringName, def: PerkDef) -> void:
	_id = id
	_def = def
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	App.player_data.biomass_changed.connect(_on_changed)

func dispose() -> void:
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.player_data.biomass_changed.disconnect(_on_changed)

# --- Commands (called by the View on user input) ---

func buy() -> bool:
	return App.buy_perk(_id)

# --- Model -> notification plumbing ---

func _on_changed(_arg = null) -> void:
	_notify(PROP_CHANGED)
