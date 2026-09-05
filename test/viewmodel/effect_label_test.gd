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
	assert_str(text).is_equal("x2 node production")

## Branching on the op rather than the size of the number: a MORE of 0.3 is the
## x1.3 its level multiplies by, and "+30%" advertises it as joining the additive
## pool it is deliberately kept out of.
func test_a_small_multiplier_still_reads_as_a_multiplier() -> void:
	var text := EffectLabel.of_effect(_effect(&"biomass_gain", UpgradeEffectDef.Op.MORE, 0.3))
	assert_str(text).is_equal("x1.3 biomass gained on sporation")

func test_an_additive_percentage_reads_as_a_percentage() -> void:
	var text := EffectLabel.of_effect(_effect(&"node_production", UpgradeEffectDef.Op.INCREASED, 0.08))
	assert_str(text).is_equal("+8% node production")

func test_a_fractional_multiplier_drops_its_padding_zeros() -> void:
	var text := EffectLabel.of_effect(_effect(&"relic_gain", UpgradeEffectDef.Op.MORE, 1.5))
	assert_str(text).is_equal("x2.5 relics from missions")

func test_a_two_place_multiplier_keeps_both() -> void:
	var text := EffectLabel.of_effect(_effect(&"relic_gain", UpgradeEffectDef.Op.MORE, 1.25))
	assert_str(text).is_equal("x2.25 relics from missions")

## The level is what the effect is worth held, which is what a perk row shows.
func test_a_level_scales_the_phrase() -> void:
	var text := EffectLabel.of_effect(_effect(&"biomass_gain", UpgradeEffectDef.Op.MORE, 0.2), 3)
	assert_str(text).is_equal("x1.6 biomass gained on sporation")

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
	assert_str(text).is_equal("-0.5s tick duration")

# ─── Resolved amounts ────────────────────────────────────────────────────────

## What the perk panel shows for the levels actually held. of_effect() multiplies
## the authored rate; this words a number the upgrade system already resolved,
## which is the only way a dependency-scaled or capped effect can be told the
## truth about.
func test_a_resolved_amount_is_worded_as_it_stands() -> void:
	var effect := _effect(&"node_production", UpgradeEffectDef.Op.INCREASED, 0.08)
	assert_str(EffectLabel.of_amount(effect, 0.34)).is_equal("+34% node production")

func test_a_resolved_amount_keeps_its_scope_and_plural() -> void:
	var effect := _effect(&"farm_slots", UpgradeEffectDef.Op.ADD, 1.0,
		UpgradeEffectDef.Scope.TAG, &"canopy")
	assert_str(EffectLabel.of_amount(effect, 3.0)).is_equal("+3 farm plots on Canopy")

func test_a_null_effect_has_no_amount() -> void:
	assert_str(EffectLabel.of_amount(null, 1.0)).is_empty()

# ─── Scope ───────────────────────────────────────────────────────────────────

## A global effect is most of them, so naming the scope on every line would say
## nothing the reader did not already assume.
func test_a_global_effect_names_no_scope() -> void:
	# On a stat whose own noun carries no "on": biomass_gain's does ("gained on
	# sporation"), and would answer this question with the noun rather than a scope.
	var text := EffectLabel.of_effect(_effect(&"automation_rate", UpgradeEffectDef.Op.MORE, 0.5))
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
	assert_str(EffectLabel.of_effects(effects)) \
		.is_equal("x1.3 biomass gained on sporation, +1 farm plot")

# ─── Scaling ─────────────────────────────────────────────────────────────────

func _source(kind: ScalingSourceDef.Kind, key: StringName) -> ScalingSourceDef:
	var source := ScalingSourceDef.new()
	source.kind = kind
	source.key = key
	return source

## An effect whose rate is multiplied by a dependency is not worth what its
## per_level says, and the percentage alone would be a number the player never
## sees happen.
func test_a_node_count_dependency_says_what_it_scales_with() -> void:
	var effect := _effect(&"synergy_production", UpgradeEffectDef.Op.INCREASED, 0.04,
		UpgradeEffectDef.Scope.NODE, &"3")
	effect.dependency = _source(ScalingSourceDef.Kind.NODE_COUNT, &"ManualNode3")
	assert_str(EffectLabel.scaling_note(effect)) \
		.is_equal(", scaled by how many of that tier you have grown")

func test_a_biome_size_dependency_names_the_biome() -> void:
	var effect := _effect(&"potency_production", UpgradeEffectDef.Op.MORE, 0.1)
	effect.dependency = _source(ScalingSourceDef.Kind.BIOME_SIZE, &"symbiosis")
	assert_str(EffectLabel.scaling_note(effect)).is_equal(", scaled by Symbiosis Size")

func test_a_biome_level_dependency_names_the_biome() -> void:
	var effect := _effect(&"node_production", UpgradeEffectDef.Op.INCREASED, 0.02)
	effect.dependency = _source(ScalingSourceDef.Kind.BIOME_LEVEL, &"crystal_caves")
	assert_str(EffectLabel.scaling_note(effect)).is_equal(", scaled by Crystal Caves Level")

func test_an_effect_that_scales_with_nothing_adds_no_clause() -> void:
	assert_str(EffectLabel.scaling_note(_effect(&"biomass_gain", UpgradeEffectDef.Op.MORE, 0.3))).is_empty()
	assert_str(EffectLabel.scaling_note(null)).is_empty()

# ─── Authored descriptions ───────────────────────────────────────────────────

func _capped(stat: StringName, op: UpgradeEffectDef.Op, per_level: float,
		cap: float) -> UpgradeEffectDef:
	var effect := _effect(stat, op, per_level)
	effect.max_magnitude = cap
	return effect

func _compound(stat: StringName, op: UpgradeEffectDef.Op, per_level: float) -> UpgradeEffectDef:
	var effect := _effect(stat, op, per_level)
	effect.level_scaling = UpgradeEffectDef.LevelScaling.COMPOUND
	return effect

func test_text_with_no_tokens_comes_back_unchanged() -> void:
	var effects: Array = [_effect(&"biomass_gain", UpgradeEffectDef.Op.MORE, 0.3)]
	assert_str(EffectLabel.expand("Water climbing uphill.", effects)) \
		.is_equal("Water climbing uphill.")

func test_value_is_the_per_level_rate_in_its_ops_own_shape() -> void:
	var more: Array = [_effect(&"water_production", UpgradeEffectDef.Op.MORE, 0.045)]
	assert_str(EffectLabel.expand("{value} water per pump.", more)) \
		.is_equal("x1.045 water per pump.")
	var increased: Array = [_effect(&"node_production", UpgradeEffectDef.Op.INCREASED, 0.08)]
	assert_str(EffectLabel.expand("{value} node production.", increased)) \
		.is_equal("+8% node production.")
	var add: Array = [_effect(&"tick_rate", UpgradeEffectDef.Op.ADD, -0.02)]
	assert_str(EffectLabel.expand("{value} tick duration.", add)).is_equal("-0.02s tick duration.")

## The sentence carries the direction in its own words, so the number must not
## carry it a second time: "Reduces Tick Timer by -0.01s" reads as an increase.
func test_magnitude_drops_the_sign_the_sentence_already_carries() -> void:
	var effects: Array = [_effect(&"tick_rate", UpgradeEffectDef.Op.ADD, -0.01)]
	assert_str(EffectLabel.expand("Reduces Tick Timer by {magnitude} per level", effects)) \
		.is_equal("Reduces Tick Timer by 0.01s per level")

## The cap is authored as an absolute bound, so it takes the direction its own
## rate runs in rather than always reading as a gain.
func test_the_cap_follows_the_direction_its_rate_runs_in() -> void:
	var effects: Array = [_capped(&"tick_rate", UpgradeEffectDef.Op.ADD, -0.02, 0.75)]
	assert_str(EffectLabel.expand("{value}, up to {cap}.", effects)).is_equal("-0.02s, up to -0.75s.")

func test_an_uncapped_effect_expands_its_cap_to_nothing() -> void:
	var effects: Array = [_effect(&"tick_rate", UpgradeEffectDef.Op.ADD, -0.02)]
	assert_str(EffectLabel.expand("{cap}", effects)).is_empty()

func test_total_is_what_every_level_comes_to() -> void:
	# COMPOUND, so 4 levels of x1.1 is 1.1^4 - 1 rather than 4 x 0.1.
	var effects: Array = [_compound(&"potency_production", UpgradeEffectDef.Op.MORE, 0.1)]
	assert_str(EffectLabel.expand("{total}", effects, 4)).is_equal("x1.464")

func test_a_compounding_effect_says_so_and_a_linear_one_does_not() -> void:
	var compound: Array = [_compound(&"water_production", UpgradeEffectDef.Op.MORE, 0.03)]
	assert_str(EffectLabel.expand("{value}, per level, {compounding}.", compound)) \
		.is_equal("x1.03, per level, compounding.")
	var linear: Array = [_effect(&"water_production", UpgradeEffectDef.Op.MORE, 0.03)]
	assert_str(EffectLabel.expand("{compounding}", linear)).is_empty()

## The clause without its leading comma, so the sentence places it itself.
func test_scaling_expands_without_the_comma_scaling_note_leads_with() -> void:
	var effect := _effect(&"potency_production", UpgradeEffectDef.Op.MORE, 0.1)
	effect.dependency = _source(ScalingSourceDef.Kind.BIOME_SIZE, &"symbiosis")
	assert_str(EffectLabel.expand("{scaling}.", [effect])).is_equal("scaled by Symbiosis Size.")

func test_max_level_reads_the_def_rather_than_an_effect() -> void:
	assert_str(EffectLabel.expand("{max_level} levels", [], 60)).is_equal("60 levels")

## A def with several effects names the one it means; without an index the first
## is what a description gets, because almost everything authored carries one.
func test_an_index_picks_an_effect_and_no_index_picks_the_first() -> void:
	var effects: Array = [
		_effect(&"water_production", UpgradeEffectDef.Op.MORE, 0.03),
		_effect(&"farm_slots", UpgradeEffectDef.Op.ADD, 2.0),
	]
	assert_str(EffectLabel.expand("{value} and {value:1}", effects)).is_equal("x1.03 and +2")

## Extras win, so a track whose numbers are not on an effect at all still writes
## one description rather than two.
func test_extras_answer_before_the_effects_do() -> void:
	var effects: Array = [_effect(&"water_production", UpgradeEffectDef.Op.MORE, 0.03)]
	assert_str(EffectLabel.expand("{rate}", effects, 0, {"rate": "x1.20"})).is_equal("x1.20")

## Left in the text rather than dropped: a sentence missing a number says nothing
## about which one, and authored_data_test fails on a visible token before it
## can ship.
func test_an_unknown_token_is_left_exactly_as_written() -> void:
	var effects: Array = [_effect(&"water_production", UpgradeEffectDef.Op.MORE, 0.03)]
	assert_str(EffectLabel.expand("{valeu} water", effects)).is_equal("{valeu} water")
	assert_array(EffectLabel.unresolved_tokens("{valeu} water", effects)) \
		.contains(["{valeu}"])

func test_an_index_past_the_effects_is_unresolved() -> void:
	var effects: Array = [_effect(&"water_production", UpgradeEffectDef.Op.MORE, 0.03)]
	assert_array(EffectLabel.unresolved_tokens("{value:4}", effects)).contains(["{value:4}"])

func test_a_description_that_resolves_leaves_nothing_behind() -> void:
	var effects: Array = [_capped(&"tick_rate", UpgradeEffectDef.Op.ADD, -0.02, 0.75)]
	assert_array(EffectLabel.unresolved_tokens("{value}, up to {cap}.", effects)).is_empty()
