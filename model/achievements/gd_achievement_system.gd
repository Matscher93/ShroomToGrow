class_name AchievementSystem
extends RefCounted
## MODEL: every rule about achievements. What each one currently measures, where
## the next tier's bar sits, what completing it pays and when to hand that out.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

## A tier's goal has been met. Nothing has been paid yet: the crystals wait on
## the player claiming it.
signal achievement_completed(id: StringName, tier: int)
signal achievement_claimed(id: StringName, tier: int, reward: BigNumber)
## Fired at the end of every evaluate(), and after any claim, so the archive has
## one refresh point. App only calls evaluate() when something actually moved,
## so this is not a per-frame signal.
signal progress_changed

## Backstop against an authored goal_growth <= 1.0, where the goal would never
## outrun the current value and the loop below would never end. The data sweep
## also rejects that, this just makes the failure a slow ladder instead of a
## hang. Leftover tiers are handed out on the next evaluate().
const MAX_TIERS_PER_EVALUATE := 100

## Ceiling on tiers one achievement may bank waiting to be claimed. Without it a
## runaway curve could pile up an unbounded claim queue.
const MAX_UNCLAIMED := 999

## Above 10^15 a float can no longer represent every integer, so rounding a
## counted goal past this point is both pointless and lossy.
const COUNT_PRECISION_EXPONENT := 15

## A tier spanning more than this many orders of magnitude gets a log-scaled
## progress bar. 3 decades is a factor of 1000: past that, linear progress sits
## visually at zero for almost the whole tier.
const LOG_SCALE_DECADES := 3.0

var _achievements: AchievementList
var _progress: AchievementProgress
var _player_data: PlayerData
var _production: ProductionSystem
var _symbiosis: UpgradeSystem
var _biomes_data: BiomesData
## id -> AchievementDef. Built once, mirroring BiomeSystem and AutomationSystem:
## claim() and claim_all() look a def up per claim, and the authored list never
## changes at runtime.
var _defs_by_id: Dictionary = {}

func _init(achievements: AchievementList, progress: AchievementProgress,
		player_data: PlayerData, production: ProductionSystem, symbiosis: UpgradeSystem,
		biomes_data: BiomesData) -> void:
	_achievements = achievements
	_progress = progress
	_player_data = player_data
	_production = production
	_symbiosis = symbiosis
	_biomes_data = biomes_data
	for def in _achievements.achievements:
		_defs_by_id[def.id] = def

# ---------------------------------------------------------------- lookup

func achievement_def(id: StringName) -> AchievementDef:
	return _defs_by_id.get(id)

## Tiers claimed. The permanent record, and Crystal Caves' XP.
func tier(id: StringName) -> int:
	return _progress.tier(id)

## Tiers completed and waiting on the player to collect them.
func unclaimed(id: StringName) -> int:
	return _progress.unclaimed_count(id)

func total_tiers() -> int:
	return _progress.total_tiers()

func total_unclaimed() -> int:
	return _progress.total_unclaimed()

func has_claims() -> bool:
	return _progress.total_unclaimed() > 0

## Counts completed tiers, claimed or not: a maxed achievement stops producing
## new goals even while its last rewards are still uncollected.
func is_maxed(def: AchievementDef) -> bool:
	return def.max_tier > 0 and _progress.completed(def.id) >= def.max_tier

# ---------------------------------------------------------------- curves

## The bar for the given tier index, where tier 0 is the very first goal.
## Counted stats are snapped to whole numbers, see _whole_goal().
func goal_for(def: AchievementDef, achievement_tier: int) -> BigNumber:
	var scaled := pow(float(achievement_tier), def.goal_growth_exponent)
	var raw := def.goal_base.mul(BigNumber.from_value(def.goal_growth).pow_float(scaled))
	if not AchievementDef.is_counted(def.stat):
		return raw
	return _whole_goal(raw, def, achievement_tier)

## Rounds a counted goal up, then holds it at least one above where tier 0 sat
## plus one per tier since.
##
## Rounding alone is not enough: a shallow curve can round two neighbouring
## tiers to the same number, and a tier whose goal matches the one before it
## completes the instant that one does, handing out a free tier. The floor term
## rises by exactly one per tier, so consecutive goals can never collide.
##
## Rounds up rather than to nearest, so the number shown is always a bar the
## player still has to clear rather than one they already passed.
func _whole_goal(raw: BigNumber, def: AchievementDef, achievement_tier: int) -> BigNumber:
	var rounded := _ceil_big(raw)
	var minimum := BigNumber.from_value(
		ceil(def.goal_base.to_float()) + float(achievement_tier))
	return minimum if minimum.gt(rounded) else rounded

## Past float's exact-integer range there is no fractional part left to round
## away, and to_float() would lose precision doing it, so the value is returned
## untouched.
func _ceil_big(value: BigNumber) -> BigNumber:
	if value.exponent > COUNT_PRECISION_EXPONENT:
		return value
	return BigNumber.from_value(ceil(value.to_float()))

## Crystals paid for completing the given tier, after every &"crystal_gain"
## upgrade has been stacked onto it.
func reward_for(def: AchievementDef, achievement_tier: int) -> BigNumber:
	var scaled := pow(float(achievement_tier), def.reward_growth_exponent)
	var base := def.reward_base.mul(BigNumber.from_value(def.reward_growth).pow_float(scaled))
	return _production.modify_crystal_gain(base)

## Where the player currently stands on this achievement's measure. Every Stat
## has to be handled here, or the achievement sits at zero forever.
func current_value(def: AchievementDef) -> BigNumber:
	match def.stat:
		AchievementDef.Stat.LIFETIME_NODES_BOUGHT:
			return BigNumber.from_value(float(_player_data.lifetime_manual_nodes))
		AchievementDef.Stat.LIFETIME_TICKS:
			return BigNumber.from_value(float(_player_data.lifetime_ticks))
		AchievementDef.Stat.LIFETIME_NUTRIENTS:
			return _player_data.lifetime_nutrients
		AchievementDef.Stat.LIFETIME_CRYSTALS:
			return _player_data.lifetime_crystals
		AchievementDef.Stat.PRESTIGE_COUNT:
			return BigNumber.from_value(float(_player_data.prestige_count))
		AchievementDef.Stat.LIFETIME_SYMBIOSIS_LEVELS:
			return BigNumber.from_value(float(_symbiosis.lifetime_levels))
		AchievementDef.Stat.LIFETIME_BIOME_SIZE:
			return BigNumber.from_value(float(_player_data.lifetime_biome_size))
		AchievementDef.Stat.PLAYER_LEVEL:
			# Derived rather than stored, so this needs no new dependency: the
			# level is a pure function of lifetime nutrients, which PlayerData
			# already holds and never resets.
			#
			# The level itself, not the Level Point budget: a perk handing out
			# points must not also hand out achievement tiers.
			return BigNumber.from_value(
				float(PlayerLevelCalculator.level_of(_player_data.lifetime_nutrients)))
		AchievementDef.Stat.BIOMES_EVER_UNLOCKED:
			var count := 0
			for key in _biomes_data.ever_unlocked:
				if _biomes_data.ever_unlocked[key]:
					count += 1
			return BigNumber.from_value(float(count))
		_:
			return BigNumber.new(0.0, 0)

## The bar the player is working towards, which is the next one not yet
## completed, whether or not the ones behind it have been claimed.
func current_goal(def: AchievementDef) -> BigNumber:
	return goal_for(def, _progress.completed(def.id))

## What claiming this achievement's next waiting tier pays. Zero when nothing is
## waiting. Priced at claim time, so &"crystal_gain" upgrades bought before
## collecting do count.
func claim_reward(def: AchievementDef) -> BigNumber:
	if _progress.unclaimed_count(def.id) <= 0:
		return BigNumber.new(0.0, 0)
	return reward_for(def, _progress.tier(def.id))

## How far into the *current tier* the player is, as 0..1. For the archive's
## progress bar only.
##
## Measured from the previous tier's goal rather than from zero. Measuring from
## zero leaves the bar sitting at goal(n-1)/goal(n) the instant a tier starts -
## 40% or more on a typical curve - so it never empties and the early part of
## every tier looks like progress the player has not made.
func progress_ratio(def: AchievementDef) -> float:
	if is_maxed(def):
		return 1.0
	var zero := BigNumber.new(0.0, 0)
	var next_tier := _progress.completed(def.id)
	var goal := current_goal(def)
	if not goal.gt(zero):
		return 1.0

	# Tier 0 has no previous bar, so it genuinely does start from zero.
	var previous := goal_for(def, next_tier - 1) if next_tier > 0 else zero
	if not previous.gt(zero):
		return clampf(current_value(def).div(goal).to_float(), 0.0, 1.0)

	var value := current_value(def)
	var span_decades := goal.log10() - previous.log10()
	if span_decades > LOG_SCALE_DECADES:
		# Orders of magnitude apart, where a linear bar would read as empty until
		# the player is nearly done. Interpolating the exponent instead keeps the
		# whole tier legible.
		if not value.gt(zero):
			return 0.0
		return clampf((value.log10() - previous.log10()) / span_decades, 0.0, 1.0)

	var span := goal.sub(previous)
	if not span.gt(zero):
		return 1.0
	return clampf(value.sub(previous).div(span).to_float(), 0.0, 1.0)

# ---------------------------------------------------------------- completing

## Banks every tier the player has crossed since the last call. Pays nothing:
## the crystals wait on a claim. A single call can complete several tiers at
## once, since an offline catch-up or a big prestige can jump more than one bar.
func evaluate() -> void:
	for def in _achievements.achievements:
		_bank_crossed_tiers(def)
	progress_changed.emit()

func _bank_crossed_tiers(def: AchievementDef) -> void:
	var banked := 0
	while banked < MAX_TIERS_PER_EVALUATE:
		if is_maxed(def) or _progress.unclaimed_count(def.id) >= MAX_UNCLAIMED:
			return
		var next_tier := _progress.completed(def.id)
		if current_value(def).lt(goal_for(def, next_tier)):
			return
		_progress.mark_completed(def.id)
		banked += 1
		achievement_completed.emit(def.id, next_tier + 1)

# ---------------------------------------------------------------- claiming

## Collects one waiting tier and pays for it. False when there was nothing to
## collect.
func claim(id: StringName) -> bool:
	var def := achievement_def(id)
	if def == null:
		return false
	var claimed_tier := _progress.tier(id)
	var reward := claim_reward(def)
	if not _progress.claim(id):
		return false
	_player_data.crystals = _player_data.crystals.add(reward)
	_player_data.lifetime_crystals = _player_data.lifetime_crystals.add(reward)
	# Kept in step with the progress model on every claim, since it is what
	# Crystal Caves reads as its XP.
	_player_data.achievement_tiers = _progress.total_tiers()
	achievement_claimed.emit(id, claimed_tier + 1, reward)
	progress_changed.emit()
	return true

## Collects everything waiting, across every achievement. Returns the total
## paid, for the "claimed +N" feedback the screen shows.
func claim_all() -> BigNumber:
	var total := BigNumber.new(0.0, 0)
	var claimed_any := false
	for def in _achievements.achievements:
		while _progress.unclaimed_count(def.id) > 0:
			var reward := claim_reward(def)
			if not _progress.claim(def.id):
				break
			total = total.add(reward)
			claimed_any = true
			achievement_claimed.emit(def.id, _progress.tier(def.id), reward)
	if not claimed_any:
		return total
	_player_data.crystals = _player_data.crystals.add(total)
	_player_data.lifetime_crystals = _player_data.lifetime_crystals.add(total)
	_player_data.achievement_tiers = _progress.total_tiers()
	progress_changed.emit()
	return total

## Rewrites the cached PlayerData projection from the progress model. Called
## after a save load, where progress is replaced wholesale.
func sync_tier_count() -> void:
	_player_data.achievement_tiers = _progress.total_tiers()
