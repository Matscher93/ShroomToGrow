class_name PerkViewModel
extends ViewModel
## VIEWMODEL: adapts one PerkDef plus the shared prestige upgrade system for
## display. One instance per perk, held in App.perk_vms. References the model,
## never a Node.

const PROP_CHANGED := &"changed"

var _id: StringName
var _def: PerkDef

# --- Static display properties (fixed for this perk's lifetime) ---
var display_name: String:
	get: return _def.display_name

var max_level: int:
	get: return _def.max_level

## The one line of prose under the perk's name: what the author wrote, or - for
## the perks that never got a description - the per-level numbers generated from
## the first effect, so the line still says something. Empty only when a perk has
## neither, and the panel hides the label rather than leaving a gap.
var description: String:
	get:
		return _def.description if not _def.description.is_empty() else _generated_effect_text()

# --- Read-only display properties bound by the View ---
var status: String:
	get: return App.perk_status(_id)

var level: int:
	get: return App.prestige_upgrade_system.level(_id)

var owned: bool:
	get: return level > 0

var level_text: String:
	get: return "%d/%d" % [level, max_level]

var tooltip_text: String:
	get: return "%s | Lv %d/%d" % [_def.display_name, level, max_level]

## the buy button carries the price, so the cost stays visible even while the perk
## is locked - "Locked" only prefixes it, it never replaces it. A maxed perk has no
## next level to price, so it's the one case without a cost.
var detail_buy_text: String:
	get:
		if level >= max_level:
			return "Maxed"
		var cost_text := "%s biomass" % App.prestige_upgrade_system.cost(_id).to_display()
		if status == "locked":
			return "Locked | %s" % cost_text
		return "Buy | %s" % cost_text

var can_buy: bool:
	get: return App.can_buy_perk(_id)

# --- Display helpers ---

## Only the first effect is described. Every perk authored so far carries one,
## and a perk with several would need wording this can't guess at - that is what
## the description field is for.
func _generated_effect_text() -> String:
	if _def.effects.is_empty():
		return ""
	var effect := _def.effects[0]
	if effect.op == UpgradeEffectDef.Op.ADD:
		return "%+.1f %s per level" % [effect.per_level, effect.stat]
	return "%+.0f%% %s per level" % [effect.per_level * 100.0, effect.stat]

# --- Lifecycle ---

func _init(id: StringName, def: PerkDef) -> void:
	_id = id
	_def = def
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	# unbind(1) drops biomass_changed's BigNumber, so the handler stays
	# parameterless.
	App.player_data.biomass_changed.connect(_on_changed.unbind(1))

func dispose() -> void:
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.player_data.biomass_changed.disconnect(_on_changed.unbind(1))

# --- Commands (called by the View on input) ---

func buy() -> bool:
	return App.buy_perk(_id)

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_CHANGED)
