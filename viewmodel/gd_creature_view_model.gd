class_name CreatureViewModel
extends ViewModel
## VIEWMODEL: one creature's card - whether it is under control, how far it has
## been pushed, and what the next rank costs.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One per authored creature, built once and owned by App: every card repaints
## when the roster or a mission-currency balance moves.

const PROP_CREATURE_CHANGED := &"creature_changed"

var _id: StringName
var _def: CreatureDef

# --- View -> ViewModel ---

func recruit() -> void:
	App.recruit_creature(_id)

func rank_up() -> void:
	App.rank_up_creature(_id)

# --- Read-only display properties bound by the View ---

var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

var is_recruited: bool:
	get: return App.is_creature_recruited(_id)

## False while the board has not been worked enough to reveal this creature. The
## card stays visible, showing what it is waiting on.
var is_unlocked: bool:
	get: return App.is_creature_unlocked(_id)

var is_busy: bool:
	get: return App.is_creature_busy(_id)

var is_maxed: bool:
	get: return App.is_creature_maxed(_id)

var rank_text: String:
	get:
		if not is_recruited:
			return "Not taken"
		return "Rank %d / %d" % [App.creature_rank(_id), App.creature_rank_cap(_id)]

## What this creature currently brings to a mission it has no affinity for. The
## affinity multiplier is shown separately, since it only applies to some.
var bonus_text: String:
	get:
		if not is_recruited:
			return ""
		var rank := float(App.creature_rank(_id))
		return "x%.2f speed  x%.2f yield" \
			% [1.0 + _def.speed_per_rank * rank, 1.0 + _def.yield_per_rank * rank]

var affinity_text: String:
	get:
		if _def.affinity.is_empty():
			return "No specialism"
		var names: PackedStringArray = []
		for mission_id in _def.affinity:
			var def := App.mission_def(mission_id)
			if def != null:
				names.append(def.display_name)
		return "x%.2f on %s" % [1.0 + _def.affinity_bonus, ", ".join(names)]

var status_text: String:
	get:
		if not is_unlocked:
			return "Opens after %d more missions" % App.missions_until_creature_unlock(_id)
		if not is_recruited:
			return "Take control for %s %s" \
				% [App.creature_recruit_cost(_id).to_display(), _currency_name(_def.recruit_currency)]
		if is_busy:
			return "Out on a mission"
		if is_maxed:
			return "As deep as it goes"
		return "Next rank: %s %s" \
			% [App.creature_rank_cost(_id).to_display(), _currency_name(_def.rank_currency)]

## The one action button's caption. The card has a single button because a
## creature is only ever in one of two states worth acting on.
var action_text: String:
	get: return "Take" if not is_recruited else "Rank up"

var can_act: bool:
	get:
		if not is_recruited:
			return App.can_recruit_creature(_id)
		return App.can_rank_up_creature(_id)

# --- Lifecycle ---

func _init(creature_id: StringName, def: CreatureDef) -> void:
	_id = creature_id
	_def = def
	App.ruins_data.creatures_changed.connect(_on_changed)
	# Being sent out and coming back both change what this card offers.
	App.ruins_data.active_changed.connect(_on_changed)
	App.ruins_data.missions_completed_changed.connect(_on_changed.unbind(1))
	# The three currencies a recruit or a rank-up is priced in.
	App.player_data.relics_changed.connect(_on_balance_changed)
	App.player_data.ichor_changed.connect(_on_balance_changed)
	App.player_data.glyphs_changed.connect(_on_balance_changed)
	# &"creature_rank_cap" comes from both tracks, so either can move the ceiling.
	App.mission_upgrade_system.upgrades_changed.connect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)

func dispose() -> void:
	App.ruins_data.creatures_changed.disconnect(_on_changed)
	App.ruins_data.active_changed.disconnect(_on_changed)
	App.ruins_data.missions_completed_changed.disconnect(_on_changed.unbind(1))
	App.player_data.relics_changed.disconnect(_on_balance_changed)
	App.player_data.ichor_changed.disconnect(_on_balance_changed)
	App.player_data.glyphs_changed.disconnect(_on_balance_changed)
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_CREATURE_CHANGED)

func _on_balance_changed(_value: BigNumber) -> void:
	_notify(PROP_CREATURE_CHANGED)

# --- Formatting ---

func _currency_name(currency: CurrencyDef) -> String:
	return currency.currency_name.to_lower() if currency != null else "relics"
