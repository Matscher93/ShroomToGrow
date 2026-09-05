class_name FertilizerViewModel
extends ViewModel
## VIEWMODEL: the fertilizer sheet and the top bar's fertilizer chip - the stock
## events have paid out, and the upgrades it buys.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One VM behind both surfaces on purpose: the chip's notification dot is exactly
## "the sheet has something affordable in it", and computing that in two places
## is how the two drift.
##
## Built once and owned by App: the chip is on screen at all times, so this
## always needs live state.

const PROP_FERT_CHANGED := &"fert_changed"

# --- View -> ViewModel ---

func buy(id: StringName) -> void:
	App.buy_fertilizer(id)

# --- Read-only display properties bound by the View ---

var balance_text: String:
	get: return "%s in stock" % App.player_data.fertilizer.to_display(0)

## The chip's notification dot: something in the sheet is affordable right now.
##
## "Affordable" rather than "you have some", because fertilizer arrives only from
## random events, in threes and fours against prices that start at three: a dot
## on every payout would light up for a stock that buys nothing. Crossing a price
## is the moment there is a decision to make - the same bar the achievement
## archive's dot uses.
var has_alert: bool:
	get:
		for upgrade in App.fertilizer_upgrade_defs():
			if App.can_buy_fertilizer(upgrade.id):
				return true
		return false

var rows: Array[FertilizerRow]:
	get:
		var built: Array[FertilizerRow] = []
		for upgrade in App.fertilizer_upgrade_defs():
			built.append(_row(upgrade))
		return built

# --- Lifecycle ---

func _init() -> void:
	App.fertilizer_upgrade_system.upgrades_changed.connect(_on_fert_changed)
	App.player_data.fertilizer_changed.connect(_on_fert_changed.unbind(1))

func dispose() -> void:
	App.fertilizer_upgrade_system.upgrades_changed.disconnect(_on_fert_changed)
	App.player_data.fertilizer_changed.disconnect(_on_fert_changed.unbind(1))

# --- Model -> notification plumbing ---

## A purchase and a payout both move the rows and the balance caption together -
## buying is what empties the stock the header shows.
func _on_fert_changed() -> void:
	_notify(PROP_FERT_CHANGED)

# --- Row building ---

func _row(upgrade: FertilizerUpgradeDef) -> FertilizerRow:
	var row := FertilizerRow.new()
	row.id = upgrade.id
	row.label = upgrade.display_name
	# A fertilizer upgrade has no UpgradeEffectDef - its payoff is one authored
	# per_level on the def - so its rate arrives as an extra.
	row.description = EffectLabel.expand(upgrade.description, [], 0,
		{"rate": "%s%%" % EffectLabel.trimmed(upgrade.per_level * 100.0)})
	row.level_text = "Lv %d" % App.fertilizer_level(upgrade.id)
	row.cost_text = App.fertilizer_cost(upgrade.id).to_display(0)
	row.enabled = App.can_buy_fertilizer(upgrade.id)
	return row
