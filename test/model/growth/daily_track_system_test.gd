extends GdUnitTestSuite
## Unit tests for DailyTrackSystem (model/growth/gd_daily_track_system.gd).
##
## Days are passed in rather than read off a clock, which is the whole reason the
## system takes `today` as a parameter: a fortnight of claims is fourteen calls,
## not fourteen days of waiting.
##
## Built against a hand-made three-slot track, so retuning the authored fourteen
## cannot turn these red.

const TODAY := 20_000

var _data: DailyRewardData
var _player: PlayerData
var _system: DailyTrackSystem

func before_test() -> void:
	_data = DailyRewardData.new()
	_player = PlayerData.new()
	_player.nutrients = BigNumber.from_value(1000.0)
	_player.water = BigNumber.from_value(500.0)
	_system = DailyTrackSystem.new(_data, _player, _build_list())

func _currency(type: CurrencyTypes.Types) -> CurrencyDef:
	var def := CurrencyDef.new()
	def.currency_type = type
	return def

func _slot(type: CurrencyTypes.Types, pct: float, floor_amount: float) -> DailyTrackSlotDef:
	var def := DailyTrackSlotDef.new()
	def.currency = _currency(type)
	def.pct_of_balance = pct
	def.min_amount = floor_amount
	return def

func _build_list() -> DailyTrackList:
	var list := DailyTrackList.new()
	var slots: Array[DailyTrackSlotDef] = [
		_slot(CurrencyTypes.Types.NUTRIENTS, 0.1, 10.0),
		_slot(CurrencyTypes.Types.WATER, 0.2, 20.0),
		_slot(CurrencyTypes.Types.NUTRIENTS, 0.5, 30.0),
	]
	list.slots = slots
	return list

# ---------------------------------------------------------------- the pass

func test_a_fresh_save_starts_on_day_one() -> void:
	assert_int(_system.claimed_days(TODAY)).is_equal(0)
	assert_int(_system.pending_day(TODAY)).is_equal(1)

func test_claiming_takes_the_pending_day() -> void:
	assert_int(_system.claim(TODAY)).is_equal(1)
	assert_int(_data.track_day).is_equal(1)

## The track stamps its own day inside claim(), so a day is a single call.
func _claim_on(day: int) -> int:
	return _system.claim(day)

func test_consecutive_days_walk_the_track() -> void:
	assert_int(_claim_on(TODAY)).is_equal(1)
	assert_int(_claim_on(TODAY + 1)).is_equal(2)
	assert_int(_claim_on(TODAY + 2)).is_equal(3)

func test_a_second_claim_on_the_same_day_pays_nothing() -> void:
	_claim_on(TODAY)
	assert_int(_system.pending_day(TODAY)).is_equal(0)
	assert_int(_system.claim(TODAY)).is_equal(0)
	assert_int(_data.track_day).is_equal(1)

# ---------------------------------------------------------------- the reset

## The rule the whole track exists for: one missed day and the fortnight starts
## over, however far in the player was.
func test_a_missed_day_resets_the_track() -> void:
	_claim_on(TODAY)
	_claim_on(TODAY + 1)
	assert_int(_system.pending_day(TODAY + 3)).is_equal(1)
	assert_int(_claim_on(TODAY + 3)).is_equal(1)

## Reading the reset off the last step's day rather than storing it is what makes the
## sheet show day one *before* anything is claimed - nothing runs on the day that
## is missed to write the zero.
## The producer chips have a day of their own: claiming every one of them leaves
## the step untouched and still waiting.
func test_the_producer_chips_do_not_take_the_step() -> void:
	_data.last_claim_day = TODAY
	assert_int(_system.pending_day(TODAY)).is_equal(1)
	assert_int(_claim_on(TODAY)).is_equal(1)

## And the reverse: taking the step is not a producer claim, so it must not move
## the day the chips and the streak run on.
func test_the_step_does_not_take_the_chips_day() -> void:
	_claim_on(TODAY)
	assert_int(_data.last_claim_day).is_zero()

func test_a_broken_pass_reads_as_broken_without_a_claim() -> void:
	_claim_on(TODAY)
	_claim_on(TODAY + 1)
	assert_int(_data.track_day).is_equal(2)
	assert_int(_system.claimed_days(TODAY + 3)).is_equal(0)

func test_a_finished_track_starts_over_the_next_day() -> void:
	_claim_on(TODAY)
	_claim_on(TODAY + 1)
	_claim_on(TODAY + 2)
	assert_int(_system.claimed_days(TODAY + 2)).is_equal(3)
	assert_int(_system.pending_day(TODAY + 3)).is_equal(1)
	assert_int(_claim_on(TODAY + 3)).is_equal(1)

func test_the_last_slot_is_reported_as_final() -> void:
	_claim_on(TODAY)
	_claim_on(TODAY + 1)
	assert_bool(_system.is_final_day(TODAY + 2)).is_true()

# ---------------------------------------------------------------- payout

func test_the_amount_scales_off_the_balance_it_pays_in() -> void:
	# Day 2 pays water: 20% of 500 clears the floor of 20.
	assert_float(_system.amount_for(2).to_float()).is_equal_approx(100.0, 0.01)

func test_the_floor_carries_a_balance_too_small_to_scale() -> void:
	_player.nutrients = BigNumber.from_value(1.0)
	assert_float(_system.amount_for(1).to_float()).is_equal_approx(10.0, 0.01)

func test_claiming_pays_the_balance_and_the_lifetime_counter() -> void:
	var before := _player.nutrients.to_float()
	var lifetime_before := _player.lifetime_nutrients.to_float()
	_claim_on(TODAY)
	assert_float(_player.nutrients.to_float()).is_equal_approx(before + 100.0, 0.01)
	assert_float(_player.lifetime_nutrients.to_float()).is_equal_approx(
		lifetime_before + 100.0, 0.01)

## Water has no lifetime counter at all - CurrencyTypes says why - so paying it
## must move the balance and stop there rather than reflect off a missing field.
func test_a_currency_without_a_lifetime_counter_still_pays() -> void:
	_claim_on(TODAY)
	var before := _player.water.to_float()
	_claim_on(TODAY + 1)
	assert_float(_player.water.to_float()).is_equal_approx(before + 100.0, 0.01)

# ---------------------------------------------------------------- unlock gate

## With no registries the map is empty and every currency reads as reachable,
## which is what the tests above rely on.
func test_an_unmapped_currency_is_paid_as_authored() -> void:
	assert_int(_system.currency_for(2)).is_equal(CurrencyTypes.Types.WATER)

## A slot whose resource the player has no screen for pays the deepest one they
## do, rather than being skipped or paid into a currency they cannot see.
func test_a_locked_currency_falls_back_to_the_deepest_reachable_one() -> void:
	var homes := CurrencyHomes.new(
		load("res://data/screens/all_screens.tres") as Screens,
		load("res://data/biomes/all_biomes.tres") as BiomeList)
	var biomes_data := BiomesData.new()
	var list := DailyTrackList.new()
	var slots: Array[DailyTrackSlotDef] = [_slot(CurrencyTypes.Types.CRYSTALS, 0.1, 10.0)]
	list.slots = slots
	var system := DailyTrackSystem.new(_data, _player, list, homes, biomes_data)
	assert_int(system.currency_for(1)).is_not_equal(CurrencyTypes.Types.CRYSTALS)
