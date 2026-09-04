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
		if _def.description.is_empty():
			return _generated_effect_text()
		return EffectLabel.expand(_def.description, _def.effects, _def.max_level,
			PerkTree.cap_step_extras(_id))

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

## What the perk is worth right now, at the level held: every effect as the
## upgrade system actually resolves it - dependency scaling and cap included -
## and not the per-level rate the description quotes. Those two part ways the
## moment a perk scales with a biome's Level, which is the number the description
## can never print.
##
## Empty while the perk is unowned, and for the cap perks, which raise somebody
## else's ceiling and carry no effect of their own to total up. The panel hides
## the label rather than showing a bonus of nothing.
var bonus_text: String:
	get:
		var lvl := level
		if lvl <= 0 or _def.effects.is_empty():
			return ""
		var parts: PackedStringArray = []
		for effect: UpgradeEffectDef in _def.effects:
			parts.append(EffectLabel.of_amount(effect,
				effect.contribution(lvl, App.resolve_context).to_float()))
		return "Now: %s" % ", ".join(parts)

var can_buy: bool:
	get: return App.can_buy_perk(_id)

# --- Display helpers ---

## Tokens a perk's description can name that are not on an effect.
##
## The cap perks are the reason: Instinct and Tide raise a boost's, an
## automation's or the whole Well's ceiling, and the step they raise it by is
## authored on the thing being raised - BoostDef.max_level_per_perk_level and its
## two counterparts - never on the perk. A description that typed the number
## would go on promising 100 levels after the boost dropped to 50, which is the
## drift this whole mechanism exists to stop.
##
## Only the first effect is described. Every perk authored so far carries one,
## and a perk with several would need wording this can't guess at - that is what
## the description field is for.
##
## Worded by EffectLabel, so a perk and an expedition reward naming the same stat
## read as the same thing. It names the scope itself - a global perk is most of
## them, and "on every node" on every line says nothing the reader did not
## assume - so all that is added here is the per-level footing and, for a perk
## that scales with something, what it scales with. Substrate's synergy perks are
## the reason for that last part: their rate is multiplied by a ScalingSourceDef,
## and the bare percentage is not what the player actually gets.
func _generated_effect_text() -> String:
	if _def.effects.is_empty():
		return ""
	var effect: UpgradeEffectDef = _def.effects[0]
	return "%s per level%s" % [EffectLabel.of_effect(effect), EffectLabel.scaling_note(effect)]

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
