class_name AutomationViewModel
extends ViewModel
## VIEWMODEL: adapts one AutomationDef plus its live level, cost and on/off state
## for the Crystal Caves automation shop. Owns formatting, derived state and
## enabled/disabled logic. References the model, never a Node.
##
## One instance per automation, built once in App._ready() and owned for the
## app's lifetime, mirroring App.perk_vms.

const PROP_LEVEL_TEXT := &"level_text"
const PROP_COST_TEXT := &"cost_text"
const PROP_CAN_BUY := &"can_buy"
const PROP_RATE_TEXT := &"rate_text"
const PROP_IS_OWNED := &"is_owned"
const PROP_IS_ENABLED := &"is_enabled"

var _def: AutomationDef

# --- Static display properties (fixed for this automation's lifetime) ---
var id: StringName:
	get: return _def.id

var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

var sort_order: int:
	get: return _def.sort_order

# --- Read-only display properties bound by the View ---
var level_text: String:
	get:
		var lvl := App.automation_level(_def.id)
		if _def.max_level <= 0:
			return "Lv %d" % [lvl]
		return "Lv %d/%d" % [lvl, _def.max_level]

var cost_text: String:
	get:
		if App.is_automation_maxed(_def.id):
			return "MAX"
		return App.automation_cost(_def.id).to_display()

var can_buy: bool:
	get: return App.can_buy_automation(_def.id)

var is_owned: bool:
	get: return App.is_automation_owned(_def.id)

var is_enabled: bool:
	get: return App.automation_data.is_enabled(_def.id)

## Blank until owned: a rate for something that never fires is noise. Below one
## action a tick it reads as a countdown, above it as a per-tick count, since
## "0.3x per tick" says much less than "every 4 ticks".
var rate_text: String:
	get:
		if not is_owned:
			return ""
		var ticks := App.automation_ticks_per_run(_def.id)
		if ticks > 1:
			return "every %d ticks" % [ticks]
		if ticks == 1:
			return "every tick"
		return "%.1fx per tick" % [App.automation_runs_per_tick(_def.id)]

# --- Lifecycle ---

func _init(def: AutomationDef) -> void:
	_def = def
	App.player_data.crystals_changed.connect(_on_crystals_changed)
	App.automation_data.levels_changed.connect(_on_levels_changed)
	App.automation_data.enabled_changed.connect(_on_enabled_changed)
	# Levels in any track can move &"automation_rate", which changes the rate.
	App.upgrade_system.upgrades_changed.connect(_on_rate_changed)
	App.biome_upgrade_system.upgrades_changed.connect(_on_rate_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_rate_changed)

func dispose() -> void:
	App.player_data.crystals_changed.disconnect(_on_crystals_changed)
	App.automation_data.levels_changed.disconnect(_on_levels_changed)
	App.automation_data.enabled_changed.disconnect(_on_enabled_changed)
	App.upgrade_system.upgrades_changed.disconnect(_on_rate_changed)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_rate_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_rate_changed)

# --- Commands (called by the View on input) ---

func buy() -> bool:
	return App.buy_automation(_def.id)

func toggle_enabled() -> void:
	App.set_automation_enabled(_def.id, not is_enabled)

# --- Model -> notification plumbing ---

func _on_crystals_changed(_value: BigNumber) -> void:
	_notify(PROP_CAN_BUY)

func _on_levels_changed() -> void:
	_notify(PROP_LEVEL_TEXT)
	_notify(PROP_COST_TEXT)
	_notify(PROP_CAN_BUY)
	_notify(PROP_RATE_TEXT)
	_notify(PROP_IS_OWNED)

func _on_enabled_changed(id: StringName) -> void:
	if id != _def.id:
		return
	_notify(PROP_IS_ENABLED)

func _on_rate_changed() -> void:
	_notify(PROP_RATE_TEXT)
