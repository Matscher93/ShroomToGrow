class_name BiomeUpgradeViewModel
extends ViewModel
## VIEWMODEL: adapts one biome upgrade (App.biome_upgrade_system entry) for
## display. Created fresh whenever BiomeUpgradeCard.select_upgrade() picks a new
## grid slot, disposed on reselect, mirroring how PrestigePanel's detail panel
## rebinds a PerkViewModel per selection. References the model, never a Node.

const PROP_CHANGED := &"changed"

var _id: StringName
var _key: StringName

# --- Read-only display properties bound by the View ---
var name_text: String:
	get:
		var def := App.biome_upgrade_system.def(_id)
		return def.display_name if def else ""

var desc_text: String:
	get:
		var def := App.biome_upgrade_system.def(_id)
		if App.is_biome_upgrade_unlocked(_id, _key):
			return def.description if def else ""
		var needed := def.min_biome_points_spent if def else 0
		return "Locked - requires %d points spent in this biome." % needed

var level_text: String:
	get: return "Lv %d" % App.biome_upgrade_system.level(_id)

var effect_text: String:
	get:
		var amount := App.biome_upgrade_system.effect_amount(_id, App.resolve_context)
		return "now +%s%%" % [amount.scale(100.0).to_display()]

var can_buy: bool:
	get: return App.can_buy_biome_upgrade(_id, _key)

# --- Lifecycle ---

func _init(id: StringName, key: StringName) -> void:
	_id = id
	_key = key
	App.biome_upgrade_system.upgrades_changed.connect(_on_changed)

func dispose() -> void:
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_changed)

# --- Commands (called by the View on input) ---

func buy() -> bool:
	return App.buy_biome_upgrade(_id, _key)

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_CHANGED)
