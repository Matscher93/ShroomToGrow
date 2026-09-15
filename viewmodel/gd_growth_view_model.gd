class_name GrowthViewModel
extends ViewModel
## VIEWMODEL: the growth sheet and the top bar's level chip - the account level,
## the Level Points it has banked, and today's daily reward.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One VM behind both surfaces on purpose: the chip's notification dot is exactly
## "the sheet has something in it", and computing that in two places is how the
## two drift.
##
## Built once and owned by App: the chip is on screen at all times, so this
## always needs live state.

const PROP_LEVEL_CHANGED := &"level_changed"
const PROP_ROWS_CHANGED := &"rows_changed"
const PROP_DAILY_CHANGED := &"daily_changed"

# --- View -> ViewModel ---

func invest(currency: CurrencyTypes.Types) -> void:
	App.invest_lp(currency)

func invest_step(currency: CurrencyTypes.Types) -> void:
	App.invest_lp_step(currency)

func claim_daily(currency: CurrencyTypes.Types) -> void:
	App.claim_daily(currency)

func claim_track() -> void:
	App.claim_daily_track()

# --- Read-only display properties bound by the View ---

var level_text: String:
	get: return "Lv %d" % App.player_level()

## The chip's bare number, which has no room for a prefix.
var level_number: String:
	get: return "%d" % App.player_level()

var level_pct: float:
	get:
		var progress := App.player_level_progress()
		return progress["pct"]

var level_progress_text: String:
	get:
		var progress := App.player_level_progress()
		var into: BigNumber = progress["into"]
		var need: BigNumber = progress["need"]
		return "%s / %s nutrients" % [into.to_display(), need.to_display()]

var lp_available: int:
	get: return App.lp_available()

var lp_available_text: String:
	get: return "%d LP free" % App.lp_available()

var global_double_text: String:
	get: return "x%s" % App.lp_global_double().to_display(0)

var global_double_next_text: String:
	get: return "x%s" % App.lp_global_double().scale(2.0).to_display(0)

## How far the current ten-point stretch has filled, for the doubling meter.
var global_pct_fill: float:
	get:
		var into := App.lp_invested_total() % PlayerLevelSystem.LP_PER_DOUBLE
		return float(into) / float(PlayerLevelSystem.LP_PER_DOUBLE)

## The whole caption under the doubling meter, composed here rather than in the
## view: two numbers spliced into a sentence is formatting, and formatting is
## the ViewModel's job.
var next_double_hint_text: String:
	get:
		return "%d LP more to reach %s" % [App.lp_points_to_next_double(),
			global_double_next_text]

var daily_ready: bool:
	get: return App.can_claim_daily()

var daily_streak_text: String:
	get: return "%d-day streak" % App.daily_streak()

## Says which of the two states the chip grid is in. Deliberately not a countdown
## to midnight: the window is a calendar day, so "tomorrow" is the whole truth
## and a ticking clock would imply a precision the rule does not have.
var daily_hint_text: String:
	get:
		if App.can_claim_daily():
			return "Claim each producer once a day for a permanent boost."
		return "All claimed today. They come back tomorrow."

## The chip's notification dot: unspent points, or a reward still waiting today.
## The dot is the only thing telling the player either exists, since the sheet is
## off screen by default - the same job the achievement archive's dot does.
var has_alert: bool:
	get:
		return App.lp_available() > 0 or App.can_claim_daily() or App.can_step_daily_track()

# --- The fourteen-day track ---

## Reads the claim state once and builds every row against it, rather than each
## row asking again: the pass boundary is a comparison against today, and a row
## built either side of a midnight that fell mid-loop would disagree with its
## neighbours.
var track_rows: Array[DailyTrackRow]:
	get:
		var rows: Array[DailyTrackRow] = []
		var claimed := App.daily_track_claimed_days()
		var pending := App.daily_track_pending_day()
		for day in range(1, App.daily_track_count() + 1):
			rows.append(_track_row(day, claimed, pending))
		return rows

## The track's own caption, beside its heading. Reads the day the player is *on*
## rather than the count behind them, which is the number the slots are labelled
## with - "Day 5 of 14" next to a highlighted D5.
var track_progress_text: String:
	get:
		var count := App.daily_track_count()
		if count == 0:
			return ""
		var pending := App.daily_track_pending_day()
		if pending == 0:
			return "Day %d of %d claimed" % [App.daily_track_claimed_days(), count]
		return "Day %d of %d" % [pending, count]

## Says where the track stands and what to do about it. The step is claimed apart
## from the chips above, so the hint has to name the press - a highlighted tile
## with no words is not an obvious button.
var track_hint_text: String:
	get:
		var count := App.daily_track_count()
		var claimed := App.daily_track_claimed_days()
		if claimed >= count and count > 0:
			return "Track complete. It starts over tomorrow."
		var pending := App.daily_track_pending_day()
		if pending == 0:
			return "Day %d claimed. Day %d arrives tomorrow." % [claimed, claimed + 1]
		if pending > 1:
			return "Tap day %d to claim it. Miss a day and the track resets." % pending
		if claimed == 0 and App.daily_streak() > 0:
			return "A missed day reset the track. Tap day 1 to start it again."
		return "Tap day 1 to start the track. Each day is worth more than the last."

func _track_row(day: int, claimed: int, pending: int) -> DailyTrackRow:
	var row := DailyTrackRow.new()
	row.day = day
	row.currency = App.daily_track_currency(day)
	var def: CurrencyDef = App.currencies.currencies.get(row.currency)
	row.accent = def.main_color if def else Color.WHITE
	row.amount_text = "+%s" % App.daily_track_amount(day).to_display(1)
	if day <= claimed:
		row.state = DailyTrackRow.State.CLAIMED
	elif day == pending:
		row.state = DailyTrackRow.State.TODAY
	else:
		row.state = DailyTrackRow.State.LOCKED
	return row

var lp_rows: Array[GrowthRow]:
	get:
		var rows: Array[GrowthRow] = []
		for producer in _producers():
			rows.append(_lp_row(producer))
		return rows

var daily_rows: Array[GrowthRow]:
	get:
		var rows: Array[GrowthRow] = []
		for producer in _producers():
			rows.append(_daily_row(producer))
		return rows

# --- Lifecycle ---

## lifetime_nutrients is a plain field with no change signal - PlayerData says
## why, and AchievementSystem rides App's per-frame dirty flag for the same
## reason. So the level binds to the tick instead, which is the only thing that
## moves it.
##
## That also covers the daily reward, whose readiness flips at local midnight
## with no input event to hang off: the tick is at most ten seconds, so the chip
## lights up on its own shortly after the day rolls over.
func _init() -> void:
	App.player_data.tick_count_changed.connect(_on_tick_count_changed)
	App.growth_upgrade_system.upgrades_changed.connect(_on_upgrades_changed)
	App.daily_reward_data.last_claim_day_changed.connect(_on_daily_changed)
	App.daily_reward_data.streak_changed.connect(_on_daily_changed)
	# The track is claimed by its own press, which moves neither of the two above.
	App.daily_reward_data.track_day_changed.connect(_on_daily_changed)
	App.daily_reward_data.track_claim_day_changed.connect(_on_daily_changed)

func dispose() -> void:
	App.player_data.tick_count_changed.disconnect(_on_tick_count_changed)
	App.growth_upgrade_system.upgrades_changed.disconnect(_on_upgrades_changed)
	App.daily_reward_data.last_claim_day_changed.disconnect(_on_daily_changed)
	App.daily_reward_data.streak_changed.disconnect(_on_daily_changed)
	App.daily_reward_data.track_day_changed.disconnect(_on_daily_changed)
	App.daily_reward_data.track_claim_day_changed.disconnect(_on_daily_changed)

# --- Model -> notification plumbing ---

func _on_tick_count_changed(_value: int) -> void:
	_notify(PROP_LEVEL_CHANGED)
	_notify(PROP_DAILY_CHANGED)

## A purchase moves the rows and the free-point count together: spending a point
## is what empties the budget the header shows.
func _on_upgrades_changed() -> void:
	_notify(PROP_ROWS_CHANGED)
	_notify(PROP_LEVEL_CHANGED)

func _on_daily_changed(_value: int) -> void:
	_notify(PROP_DAILY_CHANGED)

# --- Row building ---

func _producers() -> Array[GrowthProducerDef]:
	if App.growth_producers == null:
		return []
	return App.growth_producers.producers

func _lp_row(producer: GrowthProducerDef) -> GrowthRow:
	var currency := producer.currency.currency_type
	var invested := App.lp_invested(currency)
	# What this producer is actually multiplied by: its own additive stacks, and
	# then the doubling every producer shares. Same two factors the effects
	# resolve through, in the same order.
	var stacks := BigNumber.from_value(1.0 + producer.lp_per_level * float(invested))
	var row := _row(producer)
	row.value_text = "x%s" % stacks.mul(App.lp_global_double()).to_display(2)
	row.detail_text = "%d LP" % invested
	row.enabled = App.can_invest_lp(currency)
	var step := App.lp_step_size(currency)
	# With nothing left to spend the button is dead anyway, so it shows the points
	# the next doubling is waiting on rather than a "+0" that reads as a bug.
	row.step_text = "+%d" % (step if step > 0 else App.lp_points_to_next_double())
	row.step_enabled = step > 0
	return row

func _daily_row(producer: GrowthProducerDef) -> GrowthRow:
	var currency := producer.currency.currency_type
	var claimed := App.daily_stacks(currency)
	var row := _row(producer)
	# Shown as a percentage rather than a multiplier: daily stacks add, and "+8%"
	# after four claims reads as progress in a way "x1.08" does not.
	row.value_text = "+%d%%" % int(round(producer.daily_per_level * 100.0 * float(claimed)))
	row.detail_text = ""
	row.enabled = App.can_claim_daily_into(currency)
	return row

func _row(producer: GrowthProducerDef) -> GrowthRow:
	var row := GrowthRow.new()
	row.currency = producer.currency.currency_type
	row.label = producer.currency.currency_name
	row.accent = producer.currency.main_color
	row.text_color = producer.currency.currency_color
	return row
