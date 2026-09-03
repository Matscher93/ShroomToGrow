class_name EffectLabel
extends RefCounted
## VIEWMODEL: an UpgradeEffectDef as a phrase the player has read before -
## "x2 nutrients", "+30% biomass", "+1 farm plot".
##
## Lives here rather than under model/ for the same reason ScopeLabel does: the
## model files a contribution against &"node_production" and has no opinion about
## what to call it. This is presentation.
##
## One place, because there were about to be four. An expedition's reward is
## shown on its hero's row while it is the step in front of them, and a perk with
## no authored description already generated a sentence of its own. Several
## spellings of the same effect would have been several different words for one
## thing.

## Stats whose group noun does not read as a thing the effect moves. StatResources
## groups by the resource a stat feeds, which is the right axis for a breakdown
## and the wrong one for a sentence: &"farm_slots" feeds the "missions" group, and
## "+1 missions" is not what a farm plot is.
const NOUNS := {
	&"node_production": "nutrient production",
	&"potency_production": "potency",
	&"synergy_production": "synergy",
	&"farm_slots": "farm plot",
	&"mission_speed": "mission speed",
	&"mission_reward": "mission payout",
	&"hero_level_cap": "hero level",
	&"boost_max_level": "boost level",
	&"boost_power": "boost power",
	&"biome_points": "biome point",
	&"level_points": "level point",
	&"automation_rate": "automation speed",
	&"water_rate": "pump speed",
}

## One effect at one level, as a phrase. `level` is what the effect is worth when
## it is held - 1 for an expedition reward, which is only ever granted once.
static func of_effect(effect: UpgradeEffectDef, level: int = 1) -> String:
	if effect == null:
		return ""
	var where := ScopeLabel.suffix(ScopeLabel.of_effect(effect))
	return "%s%s" % [_magnitude(effect, level), where]

## Every effect on one upgrade, joined. Almost everything authored carries one,
## and the join is what keeps the caller from having to know that.
static func of_effects(effects: Array[UpgradeEffectDef], level: int = 1) -> String:
	var parts: PackedStringArray = []
	for effect in effects:
		var text := of_effect(effect, level)
		if text.is_empty():
			continue
		parts.append(text)
	return ", ".join(parts)

## The scaling an effect's dependency adds, as a clause to hang off the end of a
## sentence, and "" for an effect that scales with nothing.
##
## Deliberately vague about the arithmetic: the transform is what turns a count
## into a multiplier, and there is no wording for a square root that helps
## anybody. What the reader needs is that the number moves with something they
## control, and which thing that is.
static func scaling_note(effect: UpgradeEffectDef) -> String:
	if effect == null or effect.dependency == null:
		return ""
	match effect.dependency.kind:
		ScalingSourceDef.Kind.NODE_COUNT:
			return ", scaled by how many of that tier you have grown"
		ScalingSourceDef.Kind.BIOME_SIZE:
			return ", scaled by %s Size" % ScopeLabel.tag_name(String(effect.dependency.key))
		_:
			return ""

## The noun the effect moves. Falls back to the resource group, and then to the
## stat's own name, so a stat nobody has worded yet reads as itself rather than
## as nothing.
static func noun_for(stat: StringName) -> String:
	if NOUNS.has(stat):
		return NOUNS[stat]
	var group := StatResources.resource_of(String(stat))
	return String(group["resource"])

static func _magnitude(effect: UpgradeEffectDef, level: int) -> String:
	var amount := effect.per_level * float(level)
	var noun := noun_for(effect.stat)
	if effect.op == UpgradeEffectDef.Op.ADD:
		# A tick is measured in seconds, so the unit is what the number means.
		if effect.stat == &"tick_rate":
			return "%ss per tick" % _signed(amount)
		return "%s %s" % [_signed(amount), _plural(noun, amount)]
	# Anything at or past a doubling reads as the multiplier the player thinks in
	# - "x2 nutrient production", not "+100%".
	if absf(amount) >= 1.0:
		return "x%s %s" % [_trimmed(1.0 + amount), noun]
	return "%+.0f%% %s" % [amount * 100.0, noun]

## Whole counts read as whole numbers; a fractional add keeps up to two places
## with the padding zeros dropped, so half a second is "-0.5" and not "-0.50".
static func _signed(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return "%+d" % int(roundf(amount))
	return ("%+.2f" % amount).rstrip("0").rstrip(".")

static func _trimmed(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(roundf(value))
	return ("%.2f" % value).rstrip("0").rstrip(".")

## Only the counted nouns take an -s, and only away from exactly one of them.
static func _plural(noun: String, amount: float) -> String:
	if is_equal_approx(absf(amount), 1.0):
		return noun
	return "%ss" % noun
