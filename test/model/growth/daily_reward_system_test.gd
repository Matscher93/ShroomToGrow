extends GdUnitTestSuite
## Unit tests for DailyRewardSystem (model/growth/gd_daily_reward_system.gd).
##
## Time is moved through the injected now_provider rather than waited out, which
## is the only reason a day-boundary rule is testable at all. Built against a
## hand-made producer list, so retuning an authored rate cannot turn it red.

const DAY := 86400.0

var _data: DailyRewardData
var _upgrades: UpgradeSystem
var _list: GrowthProducerList
var _system: DailyRewardSystem
var _now: float

func before_test() -> void:
	# Well clear of the epoch, so a test stepping backwards stays positive.
	_now = DAY * 20_000.0
	_data = DailyRewardData.new()
	_upgrades = UpgradeSystem.new()
	_list = _build_list()
	for def in GrowthTree.build(_list):
		_upgrades.register(def)
	_system = DailyRewardSystem.new(_data, _upgrades, _list)
	_system.now_provider = func() -> float: return _now
	_system.tz_bias_provider = func() -> int: return 0

func _currency(type: CurrencyTypes.Types, currency_name: String) -> CurrencyDef:
	var def := CurrencyDef.new()
	def.currency_type = type
	def.currency_name = currency_name
	return def

func _producer(type: CurrencyTypes.Types, currency_name: String, stat: StringName) -> GrowthProducerDef:
	var def := GrowthProducerDef.new()
	def.currency = _currency(type, currency_name)
	def.stat = stat
	def.scope = UpgradeEffectDef.Scope.GLOBAL
	def.lp_per_level = 0.05
	def.daily_per_level = 0.02
	return def

func _build_list() -> GrowthProducerList:
	var list := GrowthProducerList.new()
	var producers: Array[GrowthProducerDef] = [
		_producer(CurrencyTypes.Types.NUTRIENTS, "Nutrients", &"nutrient_test"),
		_producer(CurrencyTypes.Types.WATER, "Water", &"water_test"),
	]
	list.producers = producers
	return list

# ---------------------------------------------------------------- claiming

## An untouched save has last_claim_day 0, which is 1970 - so the first reward is
## waiting the moment the player arrives, including on every save written before
## this system existed.
func test_a_fresh_save_has_a_reward_waiting() -> void:
	assert_bool(_system.can_claim()).is_true()

func test_claiming_grants_a_stack() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.stacks(CurrencyTypes.Types.WATER)).is_equal(1)

func test_claiming_uses_up_the_day() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	assert_bool(_system.can_claim()).is_false()

func test_a_second_claim_the_same_day_is_refused() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	_now += 3600.0
	assert_bool(_system.claim(CurrencyTypes.Types.NUTRIENTS)).is_false()
	assert_int(_system.stacks(CurrencyTypes.Types.NUTRIENTS)).is_zero()

func test_crossing_midnight_opens_the_next_claim() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	_now += DAY
	assert_bool(_system.can_claim()).is_true()
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.stacks(CurrencyTypes.Types.WATER)).is_equal(2)

## The window is a calendar day, not a 24-hour cooldown: claiming late one
## evening and again the next morning is two days and two claims.
func test_a_short_gap_across_midnight_still_counts_as_two_days() -> void:
	_now = DAY * 20_000.0 + 82800.0  # 23:00
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	_now += 7200.0  # 01:00 the next day
	assert_bool(_system.can_claim()).is_true()

func test_claiming_into_a_producer_that_is_not_authored_is_refused() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.CRYSTALS)).is_false()
	assert_bool(_system.can_claim()).is_true()

# ---------------------------------------------------------------- streak

func test_the_streak_counts_claims() -> void:
	assert_int(_system.streak()).is_zero()
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.streak()).is_equal(1)

func test_a_refused_claim_does_not_move_the_streak() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_false()
	assert_int(_system.streak()).is_equal(1)

## Deliberate: an idle game is played in bursts, so a missed week is not a
## reason to take the record away.
func test_the_streak_survives_a_long_gap() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	_now += DAY * 30.0
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.streak()).is_equal(2)

# ---------------------------------------------------------------- next day

## The balance simulator bounds a stride by this, so an answer that is short by a
## tick lets a run sail past the day the next reward opens on.
func test_a_full_day_is_left_at_midnight() -> void:
	assert_float(_system.seconds_until_next_day()).is_equal_approx(DAY, 0.001)

func test_the_countdown_shrinks_through_the_day() -> void:
	_now += 3600.0
	assert_float(_system.seconds_until_next_day()).is_equal_approx(DAY - 3600.0, 0.001)
	_now += DAY - 3601.0
	assert_float(_system.seconds_until_next_day()).is_equal_approx(1.0, 0.001)

func test_the_countdown_follows_the_local_offset() -> void:
	# The clock sits on a UTC midnight. Five hours west that is 19:00 the evening
	# before, so the next local midnight is five hours out, not a whole day.
	_system.tz_bias_provider = func() -> int: return -300
	assert_float(_system.seconds_until_next_day()).is_equal_approx(18000.0, 0.001)

func test_the_countdown_reaches_the_tick_the_next_claim_opens_on() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	_now += _system.seconds_until_next_day()
	assert_bool(_system.can_claim()).is_true()

# ---------------------------------------------------------------- rollback

func test_a_clock_set_back_does_not_lock_the_player_out() -> void:
	_now += DAY * 400.0
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	_now -= DAY * 400.0
	assert_bool(_system.can_claim()).is_false()
	_system.sync_clock_rollback()
	# Still not today's - the claim was spent - but tomorrow works again rather
	# than the player waiting out the 400 days the clock had jumped.
	assert_bool(_system.can_claim()).is_false()
	_now += DAY
	assert_bool(_system.can_claim()).is_true()

func test_rollback_leaves_a_sane_last_claim_alone() -> void:
	assert_bool(_system.claim(CurrencyTypes.Types.WATER)).is_true()
	var claimed_on := _data.last_claim_day
	_now += DAY * 5.0
	_system.sync_clock_rollback()
	assert_int(_data.last_claim_day).is_equal(claimed_on)
