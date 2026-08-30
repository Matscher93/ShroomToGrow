class_name BoostSystem
extends RefCounted
## MODEL: the boost economy's rules - what a boost level costs and what buying it
## takes out of the player's pocket.
##
## Boost levels are priced in crystals directly. There is no exchange step and no
## second currency: the cost curve authored on a BoostDef is already the crystal
## price.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation. Boost levels live in a plain UpgradeSystem (one def per boost per
## tier, built by BoostTree), which is what makes the boosts stack through
## ProductionSystem without any per-stat wiring here.

## What max_level() answers for a boost nothing caps. Negative so it can never be
## mistaken for a real ceiling by a caller that forgets to check - a comparison
## against it fails closed rather than reading as "maxed at -1".
const UNLIMITED := -1

var _player_data: PlayerData
var _upgrades: UpgradeSystem
var _boosts: Array[BoostDef] = []
var _by_id: Dictionary = {}   # StringName -> BoostDef
## Levels of the perks the boosts are gated behind. Read-only from here: perks
## are bought with biomass through PerkSystem, never with crystals.
var _prestige_upgrades: UpgradeSystem
## Highest tier a def has been built for, per boost id. The ladder has no last
## tier, so the defs are grown to reach rather than generated once up front.
## Only ever grows: a tier that has held a level must keep its counter.
var _top_tier: Dictionary = {}   # StringName -> int
## Resolves the two stats the Well's projects reach a boost through:
## &"boost_max_level" and &"boost_power", both scoped to a boost id. Optional so
## the suites that only exercise the crystal economy keep building this with four
## arguments.
var _production: ProductionSystem

func _init(player_data: PlayerData, upgrades: UpgradeSystem, list: BoostList,
		prestige_upgrades: UpgradeSystem, production: ProductionSystem = null) -> void:
	_player_data = player_data
	_upgrades = upgrades
	_prestige_upgrades = prestige_upgrades
	_production = production
	if list != null:
		_boosts = list.boosts
	for boost in _boosts:
		_by_id[boost.id] = boost
		# One tier is enough to open with: _grow() adds the next before it can be
		# reached, and a save's own tiers are built before its levels are read.
		_ensure_tier(boost.id, 1)

# ---------------------------------------------------------------- boosts

func boosts() -> Array[BoostDef]:
	return _boosts

func boost_def(boost_id: StringName) -> BoostDef:
	return _by_id.get(boost_id)

# ------------------------------------------------------------- growing tiers

## Builds and registers whatever tier defs are missing up to `tier`.
##
## register() keeps an existing level and only defaults a new id to zero, so
## growing an already-grown boost costs a dictionary lookup and changes nothing.
func _ensure_tier(boost_id: StringName, tier: int) -> void:
	var have := int(_top_tier.get(boost_id, 0))
	if tier <= have:
		return
	var def: BoostDef = _by_id.get(boost_id)
	if def == null:
		return
	for t in range(have + 1, tier + 1):
		var tier_def := BoostTree.build_tier(def, t)
		# BoostTree bakes the authored rate; what a level is actually bought at is
		# that scaled by the Well. A tier grown after a project was funded would
		# otherwise open at the unscaled rate until the next refresh_power().
		if not tier_def.effects.is_empty():
			tier_def.effects[0].per_level = per_level(boost_id, t)
		_upgrades.register(tier_def)
	_top_tier[boost_id] = tier

## Builds the tiers a boost needs to hold `level` levels and the next one after.
##
## The buying path grows itself; this is for a caller that puts levels in some
## other way - a save being read back, or a ladder granted rather than paid for.
func ensure_tiers_for_level(boost_id: StringName, level: int) -> void:
	_ensure_tier(boost_id, BoostTiers.tier_for_level(maxi(level, 0)))

## Keeps the tier the next level lands in built, wherever the ladder stands.
##
## One tier of headroom is enough however far a ceiling jumps: levels are bought
## one at a time, so the next level is the furthest anything can reach before
## this runs again.
func _grow(boost_id: StringName) -> void:
	ensure_tiers_for_level(boost_id, boost_level(boost_id))

## Builds the tiers a save's levels are about to be read into.
##
## UpgradeSystem.from_save() drops any id it has no def for, so a save written
## when a perk had the ladder at tier nine must find tier nine built before it
## loads - otherwise those levels are silently gone. Read off the save's own keys
## rather than off the current ceiling, because the perks and the Well projects
## that set that ceiling load either side of the boosts.
func ensure_tiers_for_save(data: Dictionary) -> void:
	for boost in _boosts:
		var prefix := "%s_t" % boost.id
		var highest := 0
		for key in data:
			var text := String(key)
			if not text.begins_with(prefix):
				continue
			var suffix := text.substr(prefix.length())
			if suffix.is_valid_int():
				highest = maxi(highest, suffix.to_int())
		if highest > 0:
			_ensure_tier(boost.id, highest)

## Levels bought across every tier of this boost. The tiers are separate level
## counters only so the per-level rate can change at each boundary; to the player
## it is one ladder.
##
## Summed to the highest tier built rather than to a last tier, since there is no
## last tier. _top_tier only ever grows, so it always covers every level ever
## bought - a level cannot exist in a tier that was never built to hold it.
func boost_level(boost_id: StringName) -> int:
	var total := 0
	for tier in range(1, int(_top_tier.get(boost_id, 0)) + 1):
		total += _upgrades.level(BoostTiers.upgrade_id(boost_id, tier))
	return total

## Tier the next level falls into, i.e. the rate it will be bought at.
func boost_tier(boost_id: StringName) -> int:
	return BoostTiers.tier_for_level(boost_level(boost_id))

## False while this boost still waits on its prestige perk. Only blocks buying:
## levels bought before the gate existed keep multiplying, the same way a locked
## automation keeps firing.
func is_unlocked(boost_id: StringName) -> bool:
	var def: BoostDef = _by_id.get(boost_id)
	if def == null:
		return false
	if def.unlock_perk_id.is_empty():
		return true
	return _prestige_upgrades.level(def.unlock_perk_id) > 0

## How far up the ladder this boost may currently be bought: its authored
## ceiling, plus whatever its perk has added, plus whatever the Well's projects
## have.
##
## UNLIMITED when the boost authors no ceiling of its own, since there is no
## ladder end left to fall back on. Every shipped boost sets base_max_level and
## leans on its cap perk for the rest, so this is the shape of a boost that was
## never meant to be gated rather than a common case.
##
## However high it goes, the ladder keeps tiering to meet it: the levels a perk
## opens past the old five-tier table are now bought at tier six and above,
## priced and paid at the rate they actually land on, instead of piling into a
## top tier that had stopped counting.
func max_level(boost_id: StringName) -> int:
	var def: BoostDef = _by_id.get(boost_id)
	if def == null:
		return 0
	if def.base_max_level <= 0:
		return UNLIMITED
	var ceiling := def.base_max_level
	if not def.max_level_perk_id.is_empty():
		ceiling += def.max_level_per_perk_level * _prestige_upgrades.level(def.max_level_perk_id)
	return maxi(0, ceiling + extra_max_levels(boost_id))

## Levels the Well's projects have added to this boost's ceiling. Zero without a
## ProductionSystem, which is what the four-argument construction leaves.
func extra_max_levels(boost_id: StringName) -> int:
	if _production == null:
		return 0
	return int(_production.stack(&"boost_max_level", BigNumber.new(0.0, 0), boost_id).to_float())

## What the Well's projects multiply this boost's per-level rate by. 1.0 when
## nothing targets it, so the authored ladder is the default.
func power(boost_id: StringName) -> float:
	if _production == null:
		return 1.0
	return maxf(0.0, _production.stack(&"boost_power", BigNumber.from_value(1.0),
		boost_id).to_float())

## The rate one level of the given tier is actually bought at: the authored rate
## scaled by whatever the Well has added. The single place that pairing is made,
## so the resolved effect and the displayed multiplier cannot disagree.
func per_level(boost_id: StringName, tier: int) -> float:
	var def: BoostDef = _by_id.get(boost_id)
	if def == null:
		return 0.0
	return def.per_level(tier) * power(boost_id)

## Rewrites every tier's effect with the rate power() now says it has, and
## re-registers it so UpgradeSystem recomputes what it contributes.
##
## Needed because a boost's per-level rate is baked into its UpgradeDef at build
## time - that is what keeps the hot path free of a context lookup per resolve.
## The rate only moves when a project is funded, so refreshing on that signal
## costs one rebuild per purchase rather than one per tick.
##
## Batched, and it has to announce itself: register() is silent by design, so
## rewriting every tier's per_level moves the numbers on every boost card without
## upgrades_changed ever firing. The cards listen to the boost and prestige
## tracks, not to the project track that triggers this, so nothing else would
## repaint them - they sat on the old multiplier until an unrelated purchase
## happened along. notify_changed() inside the batch collapses to one emit.
func refresh_power() -> void:
	if _production == null:
		return
	_upgrades.begin_batch()
	for boost in _boosts:
		for tier in range(1, int(_top_tier.get(boost.id, 0)) + 1):
			var def := _upgrades.def(BoostTiers.upgrade_id(boost.id, tier))
			if def == null or def.effects.is_empty():
				continue
			def.effects[0].per_level = per_level(boost.id, tier)
			_upgrades.register(def)
	_upgrades.notify_changed()
	_upgrades.end_batch()

func is_maxed(boost_id: StringName) -> bool:
	var ceiling := max_level(boost_id)
	return ceiling != UNLIMITED and boost_level(boost_id) >= ceiling

## What the boost currently multiplies its stat by, e.g. 2.7 for a x2.7. Every
## tier compounds into the same product, so a level bought at T3 is worth its
## whole factor on top of the tiers below rather than a share of a common pool.
##
## Computed from the tier table rather than read back out of the UpgradeSystem
## cache, so the number shown is the authored ladder even before the cache is
## rebuilt.
func boost_multiplier(boost_id: StringName) -> BigNumber:
	var total := BigNumber.from_value(1.0)
	var def: BoostDef = _by_id.get(boost_id)
	if def == null:
		return total
	for tier in range(1, int(_top_tier.get(boost_id, 0)) + 1):
		var levels := _upgrades.level(BoostTiers.upgrade_id(boost_id, tier))
		if levels <= 0:
			continue
		var rate := BigNumber.from_value(1.0 + per_level(boost_id, tier))
		total = total.mul(rate.pow_float(float(levels)))
	return total

## What one more level multiplies by, as a fraction above 1.0 (0.05 for a
## x1.05). Zero once maxed.
func next_level_gain(boost_id: StringName) -> float:
	if not _by_id.has(boost_id) or is_maxed(boost_id):
		return 0.0
	return per_level(boost_id, boost_tier(boost_id))

## Crystals the next level costs. Zero once maxed, which is also what
## can_buy_boost() reports on.
func boost_cost(boost_id: StringName) -> BigNumber:
	var def: BoostDef = _by_id.get(boost_id)
	if def == null or is_maxed(boost_id):
		return BigNumber.new(0.0, 0)
	# Off the authored curve and the total level, not off the tier's UpgradeDef.
	# The per-tier defs hold levels, not prices - see BoostTree.
	return def.cost_at(boost_level(boost_id))

func can_buy_boost(boost_id: StringName) -> bool:
	if not _by_id.has(boost_id) or is_maxed(boost_id) or not is_unlocked(boost_id):
		return false
	return _player_data.crystals.gte(boost_cost(boost_id))

func buy_boost(boost_id: StringName) -> bool:
	if not can_buy_boost(boost_id):
		return false
	# The tier the next level lands in may be one the ladder has never reached.
	_grow(boost_id)
	var tier := boost_tier(boost_id)
	var cost := boost_cost(boost_id)
	# Level first, crystals second: the level is what boost_cost() is priced off,
	# and a buy_with_points() that refuses (tier already at its cap) must not
	# leave the player short the crystals it would have charged.
	if not _upgrades.buy_with_points(BoostTiers.upgrade_id(boost_id, tier), true):
		return false
	_player_data.crystals = _player_data.crystals.sub(cost)
	return true
