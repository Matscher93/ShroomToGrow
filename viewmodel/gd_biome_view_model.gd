class_name BiomeViewModel
extends ViewModel
## VIEWMODEL — adapts one BiomeDef + the shared biome/upgrade state for
## display. Owns formatting, derived/display state, and enabled/disabled
## logic. Holds references to the model; never to any Node.
##
## The 10 per-biome upgrade cards and the Biome Size section read
## App.biome_upgrade_system / App.biome_size* directly (no per-card VM,
## mirrors how MyceliumNodePanel binds straight to App.upgrade_system) —
## this VM only owns what's shared across the whole biome card: unlock
## state, level/XP progress, and available points.

const PROP_UNLOCKED := &"unlocked"
const PROP_CAN_UNLOCK := &"can_unlock"
const PROP_LEVEL_TEXT := &"level_text"
const PROP_PROGRESS_TEXT := &"progress_text"
const PROP_PROGRESS_RATIO := &"progress_ratio"
const PROP_POINTS_TEXT := &"points_text"
const PROP_HAS_POINTS := &"has_points"

var _key: StringName
var _def: BiomeDef

# --- Static display properties (fixed for this biome's lifetime) ---
var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

var biome_color: Color:
	get: return _def.biome_color

var unlock_info_text: String:
	get: return "Unlocks %s" % _def.display_name

# --- Read-only display properties the View binds to ---
var unlocked: bool:
	get: return App.biomes_data.is_unlocked(_key)

var can_unlock: bool:
	get: return App.can_unlock_biome(_key)

var unlock_cost_text: String:
	get: return _def.unlock_cost._to_string()

var level_text: String:
	get: return "Lv %d" % App.biome_level(_key).level

var progress_text: String:
	get:
		var info := App.biome_level(_key)
		return "%d / %d %s" % [info.into, info.need, _def.xp_label]

var progress_ratio: float:
	get:
		var info := App.biome_level(_key)
		return float(info.into) / float(info.need) if info.need > 0 else 0.0

var points_available: int:
	get: return App.biome_available_points(_key)

var points_text: String:
	get: return "%d pts" % points_available

var has_points: bool:
	get: return points_available >= 1

# --- Lifecycle ---

func _init(key: StringName, def: BiomeDef) -> void:
	_key = key
	_def = def

	App.biomes_data.biome_unlocked.connect(_on_biome_unlocked)
	App.biome_upgrade_system.upgrades_changed.connect(_on_points_source_changed)
	App.upgrade_system.upgrades_changed.connect(_on_xp_source_changed)      # XpSource.SYMBIOSIS_LEVELS
	App.player_data.prestige_count_changed.connect(_on_xp_source_changed)  # XpSource.PRESTIGE_COUNT
	App.player_data.nutrients_changed.connect(_on_currency_changed)
	App.player_data.water_changed.connect(_on_currency_changed)
	App.player_data.biomass_changed.connect(_on_currency_changed)
	for node in App.nodes.mycelium_nodes:                                  # XpSource.TOTAL_NODES
		node.manual_nodes_changed.connect(_on_xp_source_changed)

func dispose() -> void:
	App.biomes_data.biome_unlocked.disconnect(_on_biome_unlocked)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_points_source_changed)
	App.upgrade_system.upgrades_changed.disconnect(_on_xp_source_changed)
	App.player_data.prestige_count_changed.disconnect(_on_xp_source_changed)
	App.player_data.nutrients_changed.disconnect(_on_currency_changed)
	App.player_data.water_changed.disconnect(_on_currency_changed)
	App.player_data.biomass_changed.disconnect(_on_currency_changed)
	for node in App.nodes.mycelium_nodes:
		node.manual_nodes_changed.disconnect(_on_xp_source_changed)

# --- Commands (called by the View on user input) ---

func unlock() -> void:
	App.unlock_biome(_key)
	# Model signal (biome_unlocked) triggers the notifications below.

# --- Model -> notification plumbing ---

func _on_biome_unlocked(key: StringName) -> void:
	if key != _key:
		return
	_notify(PROP_UNLOCKED)
	_notify(PROP_LEVEL_TEXT)
	_notify(PROP_PROGRESS_TEXT)
	_notify(PROP_PROGRESS_RATIO)
	_notify(PROP_POINTS_TEXT)
	_notify(PROP_HAS_POINTS)

func _on_points_source_changed() -> void:
	_notify(PROP_POINTS_TEXT)
	_notify(PROP_HAS_POINTS)

func _on_xp_source_changed(_arg = null) -> void:
	_notify(PROP_LEVEL_TEXT)
	_notify(PROP_PROGRESS_TEXT)
	_notify(PROP_PROGRESS_RATIO)
	_notify(PROP_POINTS_TEXT)
	_notify(PROP_HAS_POINTS)

func _on_currency_changed(_value: BigNumber) -> void:
	_notify(PROP_CAN_UNLOCK)
