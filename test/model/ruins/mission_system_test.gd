extends GdUnitTestSuite
## Unit tests for MissionSystem (model/ruins/gd_mission_system.gd).
##
## Built against a hand-authored two-mission list rather than the shipped data,
## so retuning a mission's duration or payouts cannot turn the rules red.
##
## The clock is injected everywhere. A mission measured in wall-clock seconds is
## exactly the thing a test cannot wait out, and the whole offline story - that a
## mission finishes while the game is closed - is a statement about two
## timestamps, which is only assertable with a clock you can move.

const EPS := 0.000001

var _player: PlayerData
var _biomes_data: BiomesData
var _upgrades: UpgradeSystem
var _prestige: UpgradeSystem
var _production: ProductionSystem
var _ctx: ResolveContext
var _data: RuinsData
var _creatures: CreatureSystem
var _system: MissionSystem
var _now: float = 1000.0

func before_test() -> void:
	# Reset before every test: the clock is a plain field, and a test that jumps a
	# day forward would otherwise hand the next one a start time in the past.
	_now = 1000.0
	_player = PlayerData.new()
	_player.relics = BigNumber.from_value(0.0)
	_biomes_data = BiomesData.new()
	_biomes_data.unlock(MissionSystem.RUINS_KEY)
	_upgrades = UpgradeSystem.new()
	_prestige = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		_prestige, _ctx, UpgradeSystem.new(), UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), _upgrades)
	_data = RuinsData.new()
	_creatures = CreatureSystem.new(_data, _player, _creature_list(), _production)
	_system = MissionSystem.new(_data, _player, _biomes_data, _production, _creatures,
		_mission_list(), _prestige)
	_system.now_provider = func() -> float: return _now
	_creatures.recruit(&"digger")

# ─── Fixtures ────────────────────────────────────────────────────────────────

func _payout(currency_type: CurrencyTypes.Types, gain_stat: StringName,
		mantissa: float, exponent: int) -> MissionPayoutDef:
	var currency := CurrencyDef.new()
	currency.currency_type = currency_type
	currency.currency_name = "Test"
	var payout := MissionPayoutDef.new()
	payout.currency = currency
	payout.gain_stat = gain_stat
	payout.amount = BigNumber.new(mantissa, exponent)
	return payout

func _mission_list() -> MissionList:
	var short_run := MissionDef.new()
	short_run.id = &"short_run"
	short_run.display_name = "Short Run"
	short_run.base_duration_seconds = 100.0
	short_run.min_creature_rank = 1
	short_run.min_missions_completed = 0
	short_run.payouts = [_payout(CurrencyTypes.Types.RELICS, &"relic_gain", 1.0, 1)]

	var deep_run := MissionDef.new()
	deep_run.id = &"deep_run"
	deep_run.display_name = "Deep Run"
	deep_run.base_duration_seconds = 400.0
	deep_run.min_creature_rank = 3
	deep_run.min_missions_completed = 2
	deep_run.payouts = [_payout(CurrencyTypes.Types.GLYPHS, &"glyph_gain", 5.0, 0)]

	var list := MissionList.new()
	list.missions = [short_run, deep_run]
	return list

func _creature_list() -> CreatureList:
	var currency := CurrencyDef.new()
	currency.currency_type = CurrencyTypes.Types.RELICS

	var digger := CreatureDef.new()
	digger.id = &"digger"
	digger.display_name = "Digger"
	digger.speed_per_rank = 0.0     # rank 1 is a clean x1.0, so durations read as authored
	digger.yield_per_rank = 0.0
	digger.affinity_bonus = 0.0
	digger.base_rank_cap = 5
	digger.recruit_currency = currency
	digger.recruit_cost = BigNumber.new(0.0, 0)
	digger.rank_currency = currency
	digger.rank_base_cost = BigNumber.new(0.0, 0)
	digger.rank_cost_growth = 1.0

	var idler := CreatureDef.new()
	idler.id = &"idler"
	idler.display_name = "Idler"
	idler.speed_per_rank = 0.0
	idler.yield_per_rank = 0.0
	idler.affinity_bonus = 0.0
	idler.base_rank_cap = 5
	idler.recruit_currency = currency
	idler.recruit_cost = BigNumber.new(0.0, 0)
	idler.rank_currency = currency
	idler.rank_base_cost = BigNumber.new(0.0, 0)
	idler.rank_cost_growth = 1.0

	var list := CreatureList.new()
	list.creatures = [digger, idler]
	return list

## Levels a stat on the mission track, the way a boost rung does.
func _grant_stat(id: StringName, stat: StringName, op: UpgradeEffectDef.Op,
		per_level: float, levels: int) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = op
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR
	var def := UpgradeDef.new()
	def.id = id
	def.max_level = levels
	def.effects = [effect]
	_upgrades.register(def)
	for _i in levels:
		assert_bool(_upgrades.buy_with_points(id, true)).is_true()

# ─── Sending ─────────────────────────────────────────────────────────────────

func test_sending_snapshots_the_duration_and_puts_the_creature_out() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	assert_int(instance_id).is_greater(0)
	assert_int(_system.expeditions_out()).is_equal(1)
	var entry := _data.find(instance_id)
	assert_float(entry["duration"]).is_equal_approx(100.0, EPS)
	assert_float(entry["started_at"]).is_equal_approx(1000.0, EPS)

## The board is uncapped: the roster is the only limit, so a second free creature
## can always go out alongside the first.
func test_the_board_takes_as_many_expeditions_as_there_are_creatures() -> void:
	_data.missions_completed = 5      # opens deep_run, which needs rank 3
	_creatures.recruit(&"idler")
	_data.set_rank(&"idler", 3)
	assert_int(_system.send(&"short_run", &"digger")).is_greater(0)
	assert_int(_system.send(&"deep_run", &"idler")).is_greater(0)
	assert_int(_system.expeditions_out()).is_equal(2)

## Two of the same one-shot expedition out at once would pay its one-time reward
## twice. Only reachable since the board stopped being capped.
func test_the_same_expedition_cannot_be_sent_twice_at_once() -> void:
	_creatures.recruit(&"idler")
	assert_int(_system.send(&"short_run", &"digger")).is_greater(0)
	assert_bool(_system.can_send(&"short_run", &"idler")).is_false()
	assert_int(_system.send(&"short_run", &"idler")).is_equal(0)

## ...and with nobody free, there is nothing to send. That is the limit that
## replaced the slot count, and it is one the player lifts by taking another
## creature over rather than by buying a place.
func test_an_expedition_needs_a_free_creature() -> void:
	assert_int(_system.send(&"short_run", &"digger")).is_greater(0)
	assert_bool(_system.can_send(&"short_run", &"digger")).is_false()
	assert_int(_system.send(&"short_run", &"digger")).is_equal(0)

func test_a_creature_below_the_rank_bar_cannot_be_sent() -> void:
	_data.missions_completed = 5   # opens deep_run, which needs rank 3
	assert_bool(_system.is_unlocked(&"deep_run")).is_true()
	assert_bool(_system.can_send(&"deep_run", &"digger")).is_false()
	_data.set_rank(&"digger", 3)
	assert_bool(_system.can_send(&"deep_run", &"digger")).is_true()

func test_a_locked_mission_cannot_be_sent() -> void:
	assert_bool(_system.is_unlocked(&"deep_run")).is_false()
	assert_int(_system.missions_until_unlock(&"deep_run")).is_equal(2)
	assert_int(_system.send(&"deep_run", &"digger")).is_equal(0)

func test_a_sealed_ruin_sends_nobody() -> void:
	_biomes_data.reset()
	assert_bool(_system.is_controlling()).is_false()
	assert_int(_system.send(&"short_run", &"digger")).is_equal(0)

# ─── The clock ───────────────────────────────────────────────────────────────

func test_a_mission_is_not_complete_before_its_duration_is_up() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 99.0
	var entry := _data.find(instance_id)
	assert_bool(_system.is_complete(entry)).is_false()
	assert_float(_system.seconds_remaining(entry)).is_equal_approx(1.0, EPS)
	assert_float(_system.progress_ratio(entry)).is_equal_approx(0.99, EPS)

func test_a_mission_completes_once_the_clock_passes_its_end() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 100.0
	var entry := _data.find(instance_id)
	assert_bool(_system.is_complete(entry)).is_true()
	assert_float(_system.seconds_remaining(entry)).is_equal_approx(0.0, EPS)

## The offline case. No tick is driven, nothing is replayed - a gap in the wall
## clock is the entire mechanism.
func test_a_gap_spanning_the_duration_finishes_the_mission_with_no_ticks() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 86400.0
	assert_bool(_system.is_complete(_data.find(instance_id))).is_true()
	assert_bool(_system.collect(instance_id)).is_true()
	assert_bool(_player.relics.equals(BigNumber.new(1.0, 1))).is_true()

func test_a_clock_moved_backwards_is_clamped_to_now() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now -= 500.0
	_system.sync_clock_rollback()
	var entry := _data.find(instance_id)
	assert_float(entry["started_at"]).is_equal_approx(_now, EPS)
	# And it now runs its authored length from here rather than being stuck.
	assert_float(_system.seconds_remaining(entry)).is_equal_approx(100.0, EPS)

func test_a_clock_moved_forwards_is_left_alone() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 50.0
	_system.sync_clock_rollback()
	assert_float(_data.find(instance_id)["started_at"]).is_equal_approx(1000.0, EPS)

# ─── Speed and reward ────────────────────────────────────────────────────────

func test_a_mission_speed_effect_shortens_the_next_send() -> void:
	_grant_stat(&"swift", &"mission_speed", UpgradeEffectDef.Op.MORE, 1.0, 1)
	assert_float(_system.duration_for(&"short_run", &"digger")).is_equal_approx(50.0, EPS)

## The snapshot contract: a boost bought while a creature is out does not move
## the errand it is already on.
func test_a_speed_boost_does_not_shorten_a_mission_already_in_flight() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_grant_stat(&"swift", &"mission_speed", UpgradeEffectDef.Op.MORE, 1.0, 1)
	assert_float(_data.find(instance_id)["duration"]).is_equal_approx(100.0, EPS)

func test_a_mission_reward_effect_raises_the_next_payout() -> void:
	_grant_stat(&"rich", &"mission_reward", UpgradeEffectDef.Op.MORE, 1.0, 1)
	var payouts := _system.payouts_for(&"short_run", &"digger")
	assert_int(payouts.size()).is_equal(1)
	var amount := BigNumber.new(float(payouts[0]["m"]), int(payouts[0]["e"]))
	assert_bool(amount.equals(BigNumber.new(2.0, 1))).is_true()

## Per-currency stats single out one kind of mission.
func test_a_currency_gain_effect_only_moves_that_currency() -> void:
	_grant_stat(&"glyphy", &"glyph_gain", UpgradeEffectDef.Op.MORE, 1.0, 1)
	var relic_payouts := _system.payouts_for(&"short_run", &"digger")
	var relics := BigNumber.new(float(relic_payouts[0]["m"]), int(relic_payouts[0]["e"]))
	assert_bool(relics.equals(BigNumber.new(1.0, 1))).is_true()
	var glyph_payouts := _system.payouts_for(&"deep_run", &"digger")
	var glyphs := BigNumber.new(float(glyph_payouts[0]["m"]), int(glyph_payouts[0]["e"]))
	assert_bool(glyphs.equals(BigNumber.from_value(10.0))).is_true()

func test_a_reward_boost_does_not_raise_a_mission_already_in_flight() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_grant_stat(&"rich", &"mission_reward", UpgradeEffectDef.Op.MORE, 1.0, 1)
	_now += 100.0
	assert_bool(_system.collect(instance_id)).is_true()
	assert_bool(_player.relics.equals(BigNumber.new(1.0, 1))).is_true()

# ─── Collecting ──────────────────────────────────────────────────────────────

func test_collecting_pays_out_frees_the_creature_and_counts_the_mission() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 100.0
	assert_bool(_system.collect(instance_id)).is_true()
	assert_bool(_player.relics.equals(BigNumber.new(1.0, 1))).is_true()
	assert_int(_system.expeditions_out()).is_equal(0)
	assert_int(_data.missions_completed).is_equal(1)
	assert_bool(_creatures.is_busy(&"digger")).is_false()

func test_collecting_moves_the_lifetime_total() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 100.0
	_system.collect(instance_id)
	assert_bool(_player.lifetime_relics.equals(BigNumber.new(1.0, 1))).is_true()

func test_an_unfinished_mission_cannot_be_collected() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 50.0
	assert_bool(_system.collect(instance_id)).is_false()
	assert_bool(_player.relics.equals(BigNumber.new(0.0, 0))).is_true()
	assert_int(_system.expeditions_out()).is_equal(1)

func test_collect_all_takes_every_finished_mission_and_leaves_the_rest() -> void:
	# Two different expeditions: the same one cannot be out twice at once.
	_data.missions_completed = 5      # opens deep_run, which needs rank 3
	_creatures.recruit(&"idler")
	_data.set_rank(&"idler", 3)
	var first := _system.send(&"short_run", &"digger")
	_now += 60.0
	var second := _system.send(&"deep_run", &"idler")
	_now += 50.0   # first is 110s in and done, second only 50s of its 400s
	assert_int(_system.completed_count()).is_equal(1)
	assert_int(_system.collect_all()).is_equal(1)
	assert_bool(_data.find(first).is_empty()).is_true()
	assert_bool(_data.find(second).is_empty()).is_false()

func test_the_tally_is_projected_onto_player_data() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 100.0
	_system.collect(instance_id)
	assert_int(_player.missions_completed).is_equal(1)

func test_sync_rebuilds_the_projection_after_a_load() -> void:
	_data.missions_completed = 7
	_player.missions_completed = 0
	_system.sync_missions_completed()
	assert_int(_player.missions_completed).is_equal(7)

# ─── Picking a creature ──────────────────────────────────────────────────────

## The auto-pick behind the board's one-tap send. Ranked on speed x yield, which
## is the whole of what a creature brings to an errand.

func test_the_best_creature_is_the_only_free_one() -> void:
	assert_str(String(_system.best_creature_for(&"short_run"))).is_equal("digger")

func test_nothing_is_picked_when_no_creature_is_free() -> void:
	_system.send(&"short_run", &"digger")
	assert_str(String(_system.best_creature_for(&"short_run"))).is_empty()

func test_a_busy_creature_is_never_picked() -> void:
	_creatures.recruit(&"idler")
	_system.send(&"short_run", &"digger")
	assert_str(String(_system.best_creature_for(&"short_run"))).is_equal("idler")

## Affinity rides on both multipliers, so a specialist wins the product without
## needing a rule of its own - which is exactly what this asserts.
func test_the_creature_with_affinity_wins() -> void:
	_creatures.recruit(&"idler")
	var idler := _creatures.creature_def(&"idler")
	idler.affinity = [&"short_run"]
	idler.affinity_bonus = 0.5
	assert_str(String(_system.best_creature_for(&"short_run"))).is_equal("idler")

## ...but only on the mission it is a specialist in.
func test_affinity_does_not_carry_to_another_mission() -> void:
	_creatures.recruit(&"idler")
	var idler := _creatures.creature_def(&"idler")
	idler.affinity = [&"deep_run"]
	idler.affinity_bonus = 0.5
	assert_str(String(_system.best_creature_for(&"short_run"))).is_equal("digger")

func test_the_stronger_creature_wins_without_affinity() -> void:
	_creatures.recruit(&"idler")
	var idler := _creatures.creature_def(&"idler")
	idler.speed_per_rank = 1.0
	idler.yield_per_rank = 1.0
	assert_str(String(_system.best_creature_for(&"short_run"))).is_equal("idler")

## A creature below the mission's rank bar is not a candidate, however strong.
func test_a_creature_under_the_rank_bar_is_never_picked() -> void:
	_data.missions_completed = 5   # opens deep_run, which needs rank 3
	_creatures.recruit(&"idler")
	var idler := _creatures.creature_def(&"idler")
	idler.speed_per_rank = 1.0
	idler.yield_per_rank = 1.0
	_data.set_rank(&"digger", 3)
	assert_str(String(_system.best_creature_for(&"deep_run"))).is_equal("digger")
