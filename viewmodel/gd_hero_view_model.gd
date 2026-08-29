class_name HeroViewModel
extends ViewModel
## VIEWMODEL: one hero's card - whether it is under control, how far it has
## been pushed, and what the next level costs.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One per authored hero, built once and owned by App: every card repaints
## when the roster or a mission-currency balance moves.

const PROP_CREATURE_CHANGED := &"hero_changed"

var _id: StringName
var _def: HeroDef

# --- View -> ViewModel ---

func recruit() -> void:
	App.recruit_hero(_id)

func level_up() -> void:
	App.level_up_hero(_id)

# --- Read-only display properties bound by the View ---

var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

var is_recruited: bool:
	get: return App.is_hero_recruited(_id)

## False while the board has not been worked enough to reveal this hero. The
## card stays visible, showing what it is waiting on.
var is_unlocked: bool:
	get: return App.is_hero_unlocked(_id)

var is_busy: bool:
	get: return App.is_hero_busy(_id)

var is_maxed: bool:
	get: return App.is_hero_maxed(_id)

var level_text: String:
	get:
		if not is_recruited:
			return "Not taken"
		return "Level %d / %d" % [App.hero_level(_id), App.hero_level_cap(_id)]

## What this hero's level is worth on its own expeditions.
var bonus_text: String:
	get:
		if not is_recruited:
			return ""
		var level := App.hero_level(_id)
		return "x%.2f speed  x%.2f yield" % [
			1.0 + _def.speed_per_level * level,
			1.0 + _def.yield_per_level * level,
		]

## Where this hero stands in its own chain, and what it is working towards.
var chain_text: String:
	get:
		if not is_recruited:
			return ""
		var at := App.chain_position(_id)
		var length := App.chain_length(_id)
		if at >= length:
			return "Chain walked - %d of %d" % [at, length]
		return "Chain %d / %d - next: %s" % [at, length, _next_step_name]

## What the next step is waiting on, when it is waiting on a level. Empty while
## the hero can simply be sent, which is most of the time.
var gate_text: String:
	get:
		if not is_recruited:
			return ""
		var step := App.next_chain_step(_id)
		if step == null or App.levels_until_mission_unlock(step.id) <= 0:
			return ""
		return "%s opens at level %d" % [step.display_name, step.min_hero_level]

var _next_step_name: String:
	get:
		var step := App.next_chain_step(_id)
		return step.display_name if step != null else ""

var status_text: String:
	get:
		if not is_unlocked:
			return "Opens after %d more missions" % App.missions_until_hero_unlock(_id)
		if not is_recruited:
			return "Take control for %s" % recruit_price_text
		if is_busy:
			return "Out on a mission"
		if is_maxed:
			return "As deep as it goes"
		return "Next level: %s %s" \
			% [App.hero_level_cost(_id).to_display(), _currency_name(_def.level_currency)]

## The one action button's caption. The card has a single button because a
## hero is only ever in one of two states worth acting on.
var action_text: String:
	get: return "Take" if not is_recruited else "Level up"

var can_act: bool:
	get:
		if not is_recruited:
			return App.can_recruit_hero(_id)
		return App.can_level_up_hero(_id)

# --- Lifecycle ---

func _init(hero_id: StringName, def: HeroDef) -> void:
	_id = hero_id
	_def = def
	App.ruins_data.heroes_changed.connect(_on_changed)
	# Being sent out and coming back both change what this card offers.
	App.ruins_data.active_changed.connect(_on_changed)
	App.ruins_data.missions_completed_changed.connect(_on_changed.unbind(1))
	# The three currencies a recruit or a level-up is priced in.
	App.player_data.relics_changed.connect(_on_balance_changed)
	App.player_data.ichor_changed.connect(_on_balance_changed)
	App.player_data.glyphs_changed.connect(_on_balance_changed)
	# &"hero_level_cap" comes from both tracks, so either can move the ceiling.
	App.mission_upgrade_system.upgrades_changed.connect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)

func dispose() -> void:
	App.ruins_data.heroes_changed.disconnect(_on_changed)
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

## Every currency taking this hero over costs, spelled out. One row for all but
## the last hero, which is bought with all three at once - so the card reads the
## price off a list rather than off a single cost that could not say so.
var recruit_price_text: String:
	get:
		var parts: PackedStringArray = []
		for price: Dictionary in App.hero_recruit_prices(_id):
			var amount: BigNumber = price["amount"]
			parts.append("%s %s" % [amount.to_display(), String(price["field"])])
		return " · ".join(parts)

func _currency_name(currency: CurrencyDef) -> String:
	return currency.currency_name.to_lower() if currency != null else "relics"
