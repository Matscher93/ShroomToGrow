class_name BiomeViewModel
extends ViewModel
## VIEWMODEL: adapts one BiomeDef plus the shared biome/upgrade state for
## display. Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## The 10 per-biome upgrade cards read App.biome_upgrade_system through their own
## per-selection BiomeUpgradeViewModel (see BiomeUpgradeCard). This VM owns what
## is shared across the biome card: unlock state, level and XP progress,
## available points and the Biome Size section.

const PROP_UNLOCKED := &"unlocked"
const PROP_CAN_UNLOCK := &"can_unlock"
const PROP_LEVEL_TEXT := &"level_text"
const PROP_PROGRESS_TEXT := &"progress_text"
const PROP_PROGRESS_RATIO := &"progress_ratio"
const PROP_POINTS_TEXT := &"points_text"
const PROP_HAS_POINTS := &"has_points"
const PROP_SIZE_LEVEL_TEXT := &"size_level_text"
const PROP_SIZE_COST_TEXT := &"size_cost_text"
const PROP_CAN_BUY_SIZE := &"can_buy_size"
## The upgrade slots' captions and lock state moved. Separate from
## PROP_POINTS_TEXT because the grid is spawned once and repainted per slot,
## while the points label is a single text swap.
const PROP_SLOTS_CHANGED := &"slots_changed"

var _key: StringName
var _def: BiomeDef

# --- View state ---
## Whether the card's upgrade body is open. Parked here because App owns this VM
## for the app's lifetime while the Biomes screen is freed on every nav switch
## (see GameScreens), so a flag on the card itself would spring back open on
## every visit. Same reasoning as BiomeSequenceViewModel.expanded.
## Defaults open: the upgrades are the card's whole point. Not saved - view
## state, not progress.
var expanded := true

# --- Static display properties (fixed for this biome's lifetime) ---
var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

var biome_color: Color:
	get: return _def.biome_color

var biome_shader: Shader:
	get: return _def.biome_shader

# --- Read-only display properties bound by the View ---
## What buying this biome gets you. Several biomes bring a whole nav tab with
## them, and that was advertised nowhere - the biome's one-line description was
## the only hint that unlocking it opened a screen rather than just another card.
##
## Only while the screen is still shut: after a prestige the biome relocks but
## its tab stays, so the line would be selling something the player already has.
var unlock_info_text: String:
	get:
		var body := "Unlocks %s" % _def.display_name
		if _def.screen_type == ScreenTypes.Types.BIOMES:
			return body
		if App.is_screen_unlocked(_def.screen_type):
			return body
		var screen := App.screens_vm.get_screen_data(_def.screen_type)
		if screen == null:
			return body
		return "%s and the %s screen" % [body, screen.screen_name]

var unlocked: bool:
	get: return App.biomes_data.is_unlocked(_key)

var can_unlock: bool:
	get: return App.can_unlock_biome(_key)

var unlock_cost_text: String:
	get: return _def.unlock_cost.to_display()

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
	get: return "%d pts" % [points_available]

var has_points: bool:
	get: return points_available >= 1

## Subtitle under a slot's number in the upgrade grid: how far this upgrade is
## towards its cap.
func upgrade_slot_text(id: StringName) -> String:
	var def := App.biome_upgrade_system.def(id)
	var lvl := App.biome_upgrade_system.level(id)
	if def == null or def.max_level <= 0:   # 0 = infinite, nothing to count towards
		return "%d" % lvl
	return "%d/%d" % [lvl, def.max_level]

func is_upgrade_unlocked(id: StringName) -> bool:
	return App.is_biome_upgrade_unlocked(id, _key)

var size_level_text: String:
	get: return "Lv %d" % App.biome_size(_key)

var size_cost_text: String:
	get: return App.biome_size_cost(_key).to_display()

var can_buy_size: bool:
	get: return App.can_buy_biome_size(_key)

# --- Lifecycle ---

func _init(key: StringName, def: BiomeDef) -> void:
	_key = key
	_def = def

	App.biomes_data.biome_unlocked.connect(_on_biome_unlocked)
	# Its own handler rather than _on_points_source_changed: this is the only
	# source that also moves the upgrade slots, since a purchase changes both the
	# levels they caption and the points-spent total that unlocks the later ones.
	App.biome_upgrade_system.upgrades_changed.connect(_on_biome_upgrades_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_points_source_changed)  # bonus &"biome_points" perks
	App.upgrade_system.upgrades_changed.connect(_on_xp_source_changed)      # XpSource.SYMBIOSIS_LEVELS
	# unbind(1) drops the value these signals carry, so the handler stays
	# parameterless.
	App.player_data.prestige_count_changed.connect(_on_xp_source_changed.unbind(1))  # XpSource.PRESTIGE_COUNT
	App.player_data.achievement_tiers_changed.connect(_on_xp_source_changed.unbind(1))  # XpSource.ACHIEVEMENT_TIERS
	App.player_data.well_project_levels_changed.connect(_on_xp_source_changed.unbind(1))  # XpSource.WELL_PROJECTS
	App.player_data.missions_completed_changed.connect(_on_xp_source_changed.unbind(1))  # XpSource.MISSIONS_COMPLETED
	# Every currency a biome can be priced in, so an unlock button never sits
	# stale on a balance it should be reacting to. CurrencyTypes decides what
	# unlock_currency may name, so a new one belongs here too.
	App.player_data.nutrients_changed.connect(_on_currency_changed)
	App.player_data.water_changed.connect(_on_currency_changed)
	App.player_data.biomass_changed.connect(_on_currency_changed)
	App.player_data.crystals_changed.connect(_on_currency_changed)
	for node in App.nodes.mycelium_nodes:                                  # XpSource.TOTAL_NODES
		node.manual_nodes_changed.connect(_on_xp_source_changed.unbind(1))
	App.biome_size_changed.connect(_on_biome_size_changed)

func dispose() -> void:
	App.biomes_data.biome_unlocked.disconnect(_on_biome_unlocked)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_biome_upgrades_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_points_source_changed)
	App.upgrade_system.upgrades_changed.disconnect(_on_xp_source_changed)
	App.player_data.prestige_count_changed.disconnect(_on_xp_source_changed.unbind(1))
	App.player_data.achievement_tiers_changed.disconnect(_on_xp_source_changed.unbind(1))
	App.player_data.well_project_levels_changed.disconnect(_on_xp_source_changed.unbind(1))
	App.player_data.missions_completed_changed.disconnect(_on_xp_source_changed.unbind(1))
	App.player_data.nutrients_changed.disconnect(_on_currency_changed)
	App.player_data.water_changed.disconnect(_on_currency_changed)
	App.player_data.biomass_changed.disconnect(_on_currency_changed)
	App.player_data.crystals_changed.disconnect(_on_currency_changed)
	for node in App.nodes.mycelium_nodes:
		node.manual_nodes_changed.disconnect(_on_xp_source_changed.unbind(1))
	App.biome_size_changed.disconnect(_on_biome_size_changed)

# --- Commands (called by the View on input) ---

func unlock() -> void:
	App.unlock_biome(_key)
	# The biome_unlocked model signal triggers the notifications below.

func buy_size() -> bool:
	return App.buy_biome_size(_key)

## The upgrade slots this biome's card spawns, in authored order. Static for the
## def's lifetime; it is here so the panel has no reason to reach past the VM for
## it, mirroring BiomeSequenceViewModel.upgrade_ids().
func upgrade_ids() -> Array[StringName]:
	return _def.upgrade_ids

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
	_notify(PROP_SLOTS_CHANGED)

func _on_points_source_changed() -> void:
	_notify(PROP_POINTS_TEXT)
	_notify(PROP_HAS_POINTS)

func _on_biome_upgrades_changed() -> void:
	_on_points_source_changed()
	_notify(PROP_SLOTS_CHANGED)

func _on_xp_source_changed() -> void:
	_notify(PROP_LEVEL_TEXT)
	_notify(PROP_PROGRESS_TEXT)
	_notify(PROP_PROGRESS_RATIO)
	_notify(PROP_POINTS_TEXT)
	_notify(PROP_HAS_POINTS)

func _on_currency_changed(_value: BigNumber) -> void:
	_notify(PROP_CAN_UNLOCK)
	_notify(PROP_CAN_BUY_SIZE)

func _on_biome_size_changed(key: StringName) -> void:
	if key != _key:
		return
	_notify(PROP_SIZE_LEVEL_TEXT)
	_notify(PROP_SIZE_COST_TEXT)
	_notify(PROP_CAN_BUY_SIZE)
