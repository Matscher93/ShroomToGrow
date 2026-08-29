extends GdUnitTestSuite
## Unit tests for EffectLabel (viewmodel/gd_effect_label.gd) - the one place an
## UpgradeEffectDef is turned into a phrase.
##
## Worth pinning because three screens and a generated perk description all read
## it, so a change to the wording here changes what the player is told in four
## places at once.

func _effect(stat: StringName, op: UpgradeEffectDef.Op, per_level: float,
		scope := UpgradeEffectDef.Scope.GLOBAL, target := &"") -> UpgradeEffectDef:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = op
	effect.per_level = per_level
	effect.scope = scope
	effect.target = target
	return effect

# ─── Multipliers ─────────────────────────────────────────────────────────────

## At or past a doubling the multiplier is what the player thinks in.
func test_a_doubling_reads_as_a_multiplier() -> void:
	var text := EffectLabel.of_effect(_effect(&"node_production", UpgradeEffectDef.Op.MORE, 1.0))
	assert_str(text).is_equal("x2 nutrient production")

func test_a_small_bonus_reads_as_a_percentage() -> void:
	var text := EffectLabel.of_effect(_effect(&"biomass_gain", UpgradeEffectDef.Op.MORE, 0.3))
	assert_str(text).is_equal("+30% biomass")

func test_a_fractional_multiplier_drops_its_padding_zeros() -> void:
	var text := EffectLabel.of_effect(_effect(&"crystal_gain", UpgradeEffectDef.Op.MORE, 1.5))
	assert_str(text).is_equal("x2.5 crystals")

func test_a_two_place_multiplier_keeps_both() -> void:
	var text := EffectLabel.of_effect(_effect(&"crystal_gain", UpgradeEffectDef.Op.MORE, 1.25))
	assert_str(text).is_equal("x2.25 crystals")

## The level is what the effect is worth held, which is what a perk row shows.
func test_a_level_scales_the_phrase() -> void:
	var text := EffectLabel.of_effect(_effect(&"biomass_gain", UpgradeEffectDef.Op.MORE, 0.2), 3)
	assert_str(text).is_equal("+60% biomass")

# ─── Counts ──────────────────────────────────────────────────────────────────

func test_a_single_slot_is_not_pluralised() -> void:
	var text := EffectLabel.of_effect(_effect(&"farm_slots", UpgradeEffectDef.Op.ADD, 1.0))
	assert_str(text).is_equal("+1 farm plot")

func test_several_slots_are_pluralised() -> void:
	var text := EffectLabel.of_effect(_effect(&"farm_slots", UpgradeEffectDef.Op.ADD, 1.0), 3)
	assert_str(text).is_equal("+3 farm plots")

## A tick is measured in seconds, so the unit is what the number means.
func test_a_tick_add_is_worded_in_seconds() -> void:
	var text := EffectLabel.of_effect(_effect(&"tick_rate", UpgradeEffectDef.Op.ADD, -0.5))
	assert_str(text).is_equal("-0.5s per tick")

# ─── Scope ───────────────────────────────────────────────────────────────────

## A global effect is most of them, so naming the scope on every line would say
## nothing the reader did not already assume.
func test_a_global_effect_names_no_scope() -> void:
	var text := EffectLabel.of_effect(_effect(&"biomass_gain", UpgradeEffectDef.Op.MORE, 0.5))
	assert_str(text).not_contains(" on ")

func test_a_tagged_effect_names_its_group() -> void:
	var text := EffectLabel.of_effect(_effect(&"node_production", UpgradeEffectDef.Op.MORE, 0.5,
		UpgradeEffectDef.Scope.TAG, &"canopy"))
	assert_str(text).ends_with(" on Canopy")

# ─── Fallbacks ───────────────────────────────────────────────────────────────

## A stat nobody has worded yet reads as itself rather than as nothing.
func test_an_unworded_stat_falls_back_to_its_own_name() -> void:
	assert_str(EffectLabel.noun_for(&"invented_stat")).is_equal("invented_stat")

func test_a_null_effect_is_empty() -> void:
	assert_str(EffectLabel.of_effect(null)).is_empty()

func test_several_effects_are_joined() -> void:
	var effects: Array[UpgradeEffectDef] = [
		_effect(&"biomass_gain", UpgradeEffectDef.Op.MORE, 0.3),
		_effect(&"farm_slots", UpgradeEffectDef.Op.ADD, 1.0),
	]
	assert_str(EffectLabel.of_effects(effects)).is_equal("+30% biomass, +1 farm plot")
