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

## A locked upgrade still shows what it does, so the player can plan the track
## instead of buying blind. The lock line reads as progress towards the gate
## rather than a bare requirement.
var desc_text: String:
	get:
		var def := App.biome_upgrade_system.def(_id)
		var body := def.description if def else ""
		# A scoped upgrade says which tier or group it lands on. Appended rather
		# than authored, so the ten-tiers-one-wording problem the symbiosis track
		# has cannot start here too; a global upgrade is left exactly as written.
		var scope := ScopeLabel.of_effects(def.effects) if def else ""
		if not scope.is_empty():
			body = "%s\nApplies to %s." % [body, scope]
		if App.is_biome_upgrade_unlocked(_id, _key):
			return body
		var needed := def.min_biome_points_spent if def else 0
		var spent := App.biomes_data.points_spent(_key)
		return "%s\nLocked - %d / %d points spent in this biome." % [body, spent, needed]

var level_text: String:
	get:
		var def := App.biome_upgrade_system.def(_id)
		var lvl := App.biome_upgrade_system.level(_id)
		if def == null or def.max_level <= 0:   # 0 = infinite, nothing to count towards
			return "Lv %d" % lvl
		return "Lv %d / %d" % [lvl, def.max_level]

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
