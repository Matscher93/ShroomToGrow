class_name AchievementDef
extends Resource
## MODEL: static definition of one repeatable achievement. What it measures, how
## fast the goal runs away and what each completed tier pays out.
## Parallel to BiomeDef / MyceliumNode / UpgradeDef.
##
## Achievements never "finish" unless max_tier says so: tier 0 is the first goal,
## and completing it raises the bar and the reward by the authored growth.

## What the achievement counts. Every entry has to be handled by
## AchievementSystem.current_value(), or the achievement never progresses.
##
## Append only: the ordinal is what every authored .tres stores.
##
## Every source is cumulative and survives prestige. A run-scoped one would drop
## its progress bar back to near zero on every sporation, which reads as the
## achievement being taken away.
enum Stat {
	LIFETIME_NODES_BOUGHT,      ## PlayerData.lifetime_manual_nodes
	LIFETIME_TICKS,             ## PlayerData.lifetime_ticks
	LIFETIME_NUTRIENTS,         ## PlayerData.lifetime_nutrients
	LIFETIME_CRYSTALS,          ## PlayerData.lifetime_crystals
	PRESTIGE_COUNT,             ## PlayerData.prestige_count
	LIFETIME_SYMBIOSIS_LEVELS,  ## UpgradeSystem.lifetime_levels, symbiosis track
	LIFETIME_BIOME_SIZE,        ## PlayerData.lifetime_biome_size
	BIOMES_EVER_UNLOCKED,       ## BiomesData.ever_unlocked
}

## True for stats that only ever take whole values: there is no such thing as
## 5.1 biomes unlocked or 5.8 prestiges, so a goal curve landing between two
## counts asks for something the player can never stand exactly on.
## AchievementSystem rounds those goals up and the archive renders them without
## a decimal.
##
## Defaults to true, so a counting stat added later behaves correctly without
## anyone remembering this list. Only the two genuinely continuous ones opt out.
static func is_counted(measured: Stat) -> bool:
	match measured:
		Stat.LIFETIME_NUTRIENTS, Stat.LIFETIME_CRYSTALS:
			return false
		_:
			return true

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var sort_order: int = 0  ## display order in the Crystal Caves archive
@export var stat: Stat

## Goal for tier n: goal_base * goal_growth^(n^goal_growth_exponent).
## Same curve shape as UpgradeSystem.cost() and BiomeSystem.size_cost().
@export var _goal_base_mantissa: float = 1.0
@export var _goal_base_exponent: int = 0
var goal_base: BigNumber:
	get: return BigNumber.new(_goal_base_mantissa, _goal_base_exponent)
	set(value):
		_goal_base_mantissa = value.mantissa
		_goal_base_exponent = value.exponent

## Must be > 1.0, or the goal never rises and the tier loop has nothing to stop
## it. AchievementSystem also caps its per-call iterations as a backstop.
@export var goal_growth: float = 2.0
@export var goal_growth_exponent: float = 1.0

## Crystals paid for completing tier n: reward_base * reward_growth^(n^reward_growth_exponent).
@export var _reward_base_mantissa: float = 1.0
@export var _reward_base_exponent: int = 0
var reward_base: BigNumber:
	get: return BigNumber.new(_reward_base_mantissa, _reward_base_exponent)
	set(value):
		_reward_base_mantissa = value.mantissa
		_reward_base_exponent = value.exponent

@export var reward_growth: float = 1.5
@export var reward_growth_exponent: float = 1.0

## 0 = infinite, the intended default. A positive value stops the ladder after
## that many tiers.
@export var max_tier: int = 0
