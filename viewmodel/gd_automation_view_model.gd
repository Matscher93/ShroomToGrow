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
const PROP_IS_UNLOCKED := &"is_unlocked"
const PROP_LOCK_TEXT := &"lock_text"

var _def: AutomationDef

# --- Static display properties (fixed for this automation's lifetime) ---
var id: StringName:
	get: return _def.id

var display_name: String:
	get: return _def.display_name

## An automation has no UpgradeEffectDef either - its payoff is runs per tick, on
## the def itself - so its two numbers arrive as extras rather than through an
## effect.
var description: String:
	get:
		return EffectLabel.expand(_def.description, [], _def.max_level, {
			"base_rate": EffectLabel.trimmed(_def.base_runs_per_tick),
			"rate": EffectLabel.trimmed(_def.runs_per_level),
		})

var sort_order: int:
	get: return _def.sort_order

# --- Read-only display properties bound by the View ---
## Reads the live ceiling rather than the authored one: a prestige perk can raise
## it, and a card still showing "Lv 20/20" past that would read as maxed.
var level_text: String:
	get:
		var lvl := App.automation_level(_def.id)
		var ceiling := App.automation_max_level(_def.id)
		if ceiling <= 0:
			return "Lv %d" % [lvl]
		return "Lv %d/%d" % [lvl, ceiling]

## Price only. The lock notice used to live here, which put a sentence in the
## label that is tinted the crystal colour everywhere else on the screen - it
## read as a price. It has its own line now, see lock_text.
var cost_text: String:
	get:
		if not is_unlocked:
			return ""
		if App.is_automation_maxed(_def.id):
			return "MAX"
		return App.automation_cost(_def.id).to_display()

## Why this card cannot be bought yet, and where to go about it. Empty once
## unlocked.
##
## The card stays visible while locked - a hidden one gives the player nothing to
## work towards - but naming the perk was not enough on its own: the perk web is
## a screen away and several branches wide, so the line names the branch too.
var lock_text: String:
	get:
		if is_unlocked:
			return ""
		return "Locked - needs %s (Prestige > %s)" % [_unlock_perk_name(), _unlock_branch_name()]

var can_buy: bool:
	get: return App.can_buy_automation(_def.id)

var is_owned: bool:
	get: return App.is_automation_owned(_def.id)

## False while this automation waits on its prestige perk. The card stays
## visible: a hidden one gives the player nothing to work towards.
var is_unlocked: bool:
	get: return App.is_automation_unlocked(_def.id)

var is_enabled: bool:
	get: return App.automation_data.is_enabled(_def.id)

## Blank until owned: a rate for something that never fires is noise. Below one
## action a tick it reads as a countdown, above it as a per-tick count, since
## "0.3x per tick" says much less than "every 4 ticks".
var rate_text: String:
	get:
		if not is_owned:
			return ""
		return _rate_at(App.automation_level(_def.id))

## What the next level buys, so the price on the card has something to be weighed
## against. Blank while locked or maxed, and while the next level would round to
## the same reading - "every 2 ticks -> every 2 ticks" is worse than silence.
var next_rate_text: String:
	get:
		if not is_unlocked or App.is_automation_maxed(_def.id):
			return ""
		var next := _rate_at(App.automation_level(_def.id) + 1)
		if not is_owned:
			return next
		var current := _rate_at(App.automation_level(_def.id))
		if next == current:
			return ""
		return "-> %s" % [next]

# --- Lifecycle ---

func _init(def: AutomationDef) -> void:
	_def = def
	App.player_data.crystals_changed.connect(_on_crystals_changed)
	App.automation_data.levels_changed.connect(_on_levels_changed)
	App.automation_data.enabled_changed.connect(_on_enabled_changed)
	# Levels in any track can move &"automation_rate", which changes the rate.
	App.upgrade_system.upgrades_changed.connect(_on_rate_changed)
	App.biome_upgrade_system.upgrades_changed.connect(_on_rate_changed)
	# Perks move more than the rate: they are what unlocks this automation and
	# what raises its ceiling, so the whole card is re-read.
	App.prestige_upgrade_system.upgrades_changed.connect(_on_perks_changed)

func dispose() -> void:
	App.player_data.crystals_changed.disconnect(_on_crystals_changed)
	App.automation_data.levels_changed.disconnect(_on_levels_changed)
	App.automation_data.enabled_changed.disconnect(_on_enabled_changed)
	App.upgrade_system.upgrades_changed.disconnect(_on_rate_changed)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_rate_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_perks_changed)

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

func _on_perks_changed() -> void:
	_notify(PROP_RATE_TEXT)
	_notify(PROP_IS_UNLOCKED)
	_notify(PROP_LOCK_TEXT)
	_notify(PROP_LEVEL_TEXT)
	_notify(PROP_COST_TEXT)
	_notify(PROP_CAN_BUY)

# --- Formatting ---

## Below one action a tick it reads as a countdown, above it as a per-tick count,
## since "0.3x per tick" says much less than "every 4 ticks".
func _rate_at(lvl: int) -> String:
	var ticks := App.automation_ticks_per_run_at(_def.id, lvl)
	if ticks > 1:
		return "every %d ticks" % [ticks]
	if ticks == 1:
		return "every tick"
	return "%.1fx per tick" % [App.automation_runs_per_tick_at(_def.id, lvl)]

func _unlock_perk_name() -> String:
	var def := App.perk_def(_def.unlock_perk_id)
	return def.display_name if def != null else "a prestige perk"

func _unlock_branch_name() -> String:
	var def := App.perk_def(_def.unlock_perk_id)
	if def == null:
		return "the web"
	var branch := App.perk_branches.branch(def.branch_key)
	return branch.label if branch != null else "the web"
