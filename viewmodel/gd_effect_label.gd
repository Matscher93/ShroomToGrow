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
##
## Every stat in StatNames.ALL is worded here, because a description resolving
## {noun} through the StatResources fallback would print the bucket's name - a
## &"crystal_gain" boon reading "crystals" where the card it replaces said
## "crystals from achievements". authored_data_test asserts the set stays whole.
const NOUNS := {
	&"node_production": "node production",
	&"potency_production": "potency",
	&"synergy_production": "synergy",
	&"farm_slots": "farm plot",
	&"workers_per_farm": "worker per farm",
	&"mission_speed": "mission speed",
	&"mission_reward": "mission payout",
	&"hero_level_cap": "hero level",
	&"boost_max_level": "max level",
	&"boost_power": "strength",
	&"biome_points": "biome point",
	&"level_points": "Level Point",
	&"automation_rate": "automation triggers per tick",
	&"tick_rate": "tick duration",
	&"water_rate": "ticks between pumps",
	&"water_production": "water per pump",
	&"biomass_gain": "biomass gained on sporation",
	&"crystal_gain": "crystals from achievements",
	&"relic_gain": "relics from missions",
	&"ichor_gain": "ichor from missions",
	&"glyph_gain": "glyphs from missions",
}

## Stats whose noun is a measure rather than a count of things, so it never takes
## an -s: a tick's duration is "-0.5s tick duration" at any size, and the gap
## between pumps is already worded in the plural.
const UNCOUNTED: Array[StringName] = [&"tick_rate", &"water_rate"]

## The unit an ADD on this stat is measured in, appended to the bare number. A
## tick is seconds; the gap between pumps is ticks, which the noun already says.
const UNITS := {
	&"tick_rate": "s",
}

## One effect at one level, as a phrase. `level` is what the effect is worth when
## it is held - 1 for an expedition reward, which is only ever granted once.
static func of_effect(effect: UpgradeEffectDef, level: int = 1) -> String:
	if effect == null:
		return ""
	return of_amount(effect, effect.per_level * float(level))

## The same phrase from an amount somebody else already worked out - what
## UpgradeEffectDef.contribution() resolved for the levels actually held,
## dependency scaling and cap included - rather than from per_level times a
## count. of_effect() is the authored rate; this is what the player has.
static func of_amount(effect: UpgradeEffectDef, amount: float) -> String:
	if effect == null:
		return ""
	var noun := noun_for(effect.stat)
	if effect.op == UpgradeEffectDef.Op.ADD and not UNCOUNTED.has(effect.stat):
		noun = _plural(noun, amount)
	var where := ScopeLabel.suffix(ScopeLabel.of_effect(effect))
	return "%s %s%s" % [_amount_text(effect, amount), noun, where]

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
		ScalingSourceDef.Kind.BIOME_LEVEL:
			return ", scaled by %s Level" % ScopeLabel.tag_name(String(effect.dependency.key))
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

# --- Authored descriptions ---------------------------------------------------

## The tokens a description may carry: a name, optionally followed by ":N" to
## pick an effect on a def that has several. Lowercase and underscores only, so
## a brace in ordinary prose is left alone rather than read as a broken token.
const TOKEN_PATTERN := "\\{([a-z_]+)(?::(\\d+))?\\}"

static var _token_re: RegEx = null

## Resolves the {token}s in an authored description against the effects behind
## it, so a retuned per_level reaches every card that describes it and the number
## is never authored twice.
##
## Every token reads the *per-level* rate, because that is what the sentences
## say: "+8% node production, per level". {total} is the exception, and names its
## own subject.
##
## An unknown token is left in the text exactly as written rather than dropped.
## A typo that renders as nothing is a sentence missing a number with nothing to
## say which one; a visible "{valeu}" is a bug report, and authored_data_test
## fails on one before it can ship.
##
## `extras` carries tokens that are not on an UpgradeEffectDef at all - an
## automation's runs per level, the Well's per-perk depth step - so a track with
## its own shape of number still writes one description rather than two.
static func expand(text: String, effects: Array, max_level: int = 0,
		extras: Dictionary = {}) -> String:
	if not text.contains("{"):
		return text
	var matches := _tokens().search_all(text)
	var out := text
	# Applied back to front: a replacement earlier in the string would move every
	# later match's offsets out from under it.
	for i in range(matches.size() - 1, -1, -1):
		var found := matches[i]
		var replacement: Variant = _resolve(found.get_string(1), found.get_string(2),
			effects, max_level, extras)
		if replacement == null:
			continue
		out = out.substr(0, found.get_start()) + String(replacement) + out.substr(found.get_end())
	return out

## Every token in `text` that expand() would not resolve. Empty for a description
## that is ready to ship; the integrity sweep asserts on it.
static func unresolved_tokens(text: String, effects: Array, max_level: int = 0,
		extras: Dictionary = {}) -> PackedStringArray:
	var unknown: PackedStringArray = []
	if not text.contains("{"):
		return unknown
	for found in _tokens().search_all(text):
		if _resolve(found.get_string(1), found.get_string(2), effects, max_level, extras) == null:
			unknown.append(found.get_string(0))
	return unknown

static func _tokens() -> RegEx:
	if _token_re == null:
		_token_re = RegEx.new()
		_token_re.compile(TOKEN_PATTERN)
	return _token_re

## One token's text, or null for a name nothing answers to - which is what keeps
## expand() from replacing it.
##
## `extras` is consulted first, so a track can word a token its own way without
## needing a name no other track uses.
static func _resolve(name: String, index_text: String, effects: Array, max_level: int,
		extras: Dictionary) -> Variant:
	if extras.has(name):
		return String(extras[name])
	if name == "max_level":
		return "%d" % max_level
	var index := int(index_text) if not index_text.is_empty() else 0
	if index >= effects.size():
		return null
	var effect: UpgradeEffectDef = effects[index]
	if effect == null:
		return null
	match name:
		"effect": return of_effect(effect)
		"value": return value_of(effect)
		"magnitude": return magnitude_of(effect)
		"noun": return noun_for(effect.stat)
		"cap": return cap_of(effect)
		"total": return total_of(effect, max_level)
		"scope": return ScopeLabel.of_effect(effect)
		# Without the comma the note leads with: a description places it itself.
		"scaling": return scaling_note(effect).trim_prefix(", ")
		"compounding": return compounding_note(effect).trim_prefix(", ")
		_: return null

# --- Phrases -----------------------------------------------------------------

## The clause a compounding effect needs, and "" for a linear one.
##
## A COMPOUND level multiplies by its rate again rather than adding it, so the
## authored figure is what one more level is worth and not what the levels come
## to - which is a different promise, and the word is what tells them apart.
static func compounding_note(effect: UpgradeEffectDef) -> String:
	if effect == null or effect.level_scaling != UpgradeEffectDef.LevelScaling.COMPOUND:
		return ""
	return ", compounding"

## The ceiling clause, and "" for an uncapped effect. The cap is authored as an
## absolute bound, so it takes the direction its own rate runs in - a cap of 0.75
## on a -0.02/level effect stops at -0.75s, not at +0.75s.
static func cap_note(effect: UpgradeEffectDef) -> String:
	var text := cap_of(effect)
	return "" if text.is_empty() else ", up to %s" % text

## One effect's magnitude as a bare signed number, without the noun it moves -
## "+8%", "x1.03", "-0.02s". What a description means by {value}.
static func value_of(effect: UpgradeEffectDef, level: int = 1) -> String:
	if effect == null:
		return ""
	return _amount_text(effect, effect.per_level * float(level))

## value_of() without the sign, for a sentence carrying the direction in its own
## words: "Reduces Tick Timer by 0.01s", where "-0.01s" would read as an increase.
static func magnitude_of(effect: UpgradeEffectDef, level: int = 1) -> String:
	return value_of(effect, level).trim_prefix("+").trim_prefix("-")

## The most this effect may ever contribute, in the units its rate is authored
## in, and "" for an uncapped one.
static func cap_of(effect: UpgradeEffectDef) -> String:
	if effect == null or effect.max_magnitude <= 0.0:
		return ""
	var direction := -1.0 if effect.per_level < 0.0 else 1.0
	return _amount_text(effect, effect.max_magnitude * direction)

## What the effect is worth with every level of it held. Read through
## magnitude(), so a COMPOUND effect reports what its levels actually come to
## rather than its rate times the count.
static func total_of(effect: UpgradeEffectDef, max_level: int) -> String:
	if effect == null or max_level <= 0:
		return ""
	return _amount_text(effect, effect.magnitude(max_level).to_float())

## An amount in the shape its op actually applies in.
##
## Branching on the op rather than on the size of the number, because the two say
## different things: a MORE of 0.03 is the x1.03 the level multiplies by, and
## printing it as "+3%" advertises it as joining the additive pool every
## INCREASED upgrade on the stat shares, where each level is worth less than the
## one before. An ADD on tick_rate is six hundredths of a second, not a percent
## of anything.
static func _amount_text(effect: UpgradeEffectDef, amount: float) -> String:
	match effect.op:
		UpgradeEffectDef.Op.MORE:
			return "x%s" % trimmed(1.0 + amount)
		UpgradeEffectDef.Op.ADD:
			return "%s%s" % [_signed(amount), UNITS.get(effect.stat, "")]
		_:
			return "%s%%" % _signed(amount * 100.0)

## Whole counts read as whole numbers; a fractional add keeps up to three places
## with the padding zeros dropped, so half a second is "-0.5" and not "-0.500".
##
## Three rather than two because the Well's rungs converted into halves of a
## hundredth: at two places a x1.045 and a x1.04 print the same.
static func _signed(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return "%+d" % int(roundf(amount))
	return ("%+.3f" % amount).rstrip("0").rstrip(".")

static func trimmed(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(roundf(value))
	return ("%.3f" % value).rstrip("0").rstrip(".")

## Only the counted nouns take an -s, and only away from exactly one of them.
static func _plural(noun: String, amount: float) -> String:
	if is_equal_approx(absf(amount), 1.0):
		return noun
	return "%ss" % noun
