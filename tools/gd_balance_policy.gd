class_name BalancePolicy
extends RefCounted
## TOOL: how a simulated player spends, used by gd_balance_sim.gd.
##
## Every purchase goes through the same public App entry point the UI uses, so a
## simulated run can never buy something a real one could not. Nothing here
## knows a formula; it only decides what to buy next out of what the game says
## is affordable.
##
## Progression purchases - unlocking a biome, spending biome points, buying a
## perk, growing a biome - are taken by every policy as soon as they are
## affordable, because they are not really choices: the game hands them out on
## its own through automations, and a policy that skipped them would measure a
## way nobody plays. What the policies actually differ on is the one real
## decision, nodes versus symbiosis levels.

## Which purchase the policy prefers when several are affordable.
enum Kind {
	NODES_ONLY,   ## nodes and nothing else - the floor every other run beats
	CHEAPEST,     ## whatever costs least right now
	ROI,          ## most effect gained per nutrient spent
}

## Ceiling on purchases in one tick. A late run can afford hundreds of levels per
## tick, and the shopping loop walks every candidate each time round.
const MAX_PURCHASES_PER_TICK := 40

var _app: Node
var _kind: Kind
## Symbiosis ids, read once from the same loader App registers them with.
var _symbiosis_ids: Array[StringName] = []

func _init(app: Node, kind: Kind) -> void:
	_app = app
	_kind = kind
	for def in UpgradeDefLoader.load_all(UpgradeDefLoader.SYMBIOSIS_PATH):
		_symbiosis_ids.append(def.id)


static func kind_from_name(text: String) -> Kind:
	match text.to_lower():
		"nodes_only", "nodes": return Kind.NODES_ONLY
		"cheapest": return Kind.CHEAPEST
		_: return Kind.ROI


static func name_of(kind: Kind) -> String:
	match kind:
		Kind.NODES_ONLY: return "nodes_only"
		Kind.CHEAPEST: return "cheapest"
		_: return "roi"


## Spends everything this tick's income allows. Returns how many purchases were
## made, which the simulator records as activity.
##
## Progression is swept once per tick, not once per shopping attempt. Nothing it
## buys is priced in nutrients except a biome, so re-scanning every biome, perk
## and automation after each node purchase found the same nothing forty times
## over - it was the single most expensive thing in a simulated run. Anything the
## tick's node purchases *do* unlock is picked up by the next tick's sweep, one
## tick later than before.
##
## Batched for the same reason App.handle_tick() batches the automation pass, and
## it matters more here: a tick can buy dozens of levels, every one of them
## emitting upgrades_changed to every ViewModel App built, and those ViewModels
## exist headlessly too. The player sees one tick, so they get one refresh.
func spend() -> int:
	_begin_batch()
	var bought := 0
	if _kind != Kind.NODES_ONLY:
		for _sweep in MAX_PURCHASES_PER_TICK:
			var made := _progression()
			if made == 0:
				break
			bought += made
	var budget := MAX_PURCHASES_PER_TICK
	while budget > 0:
		var made := _buy_best(budget)
		if made == 0:
			break
		budget -= made
		bought += made
	_end_batch()
	return bought


func _begin_batch() -> void:
	for system: UpgradeSystem in _tracks():
		system.begin_batch()


func _end_batch() -> void:
	for system: UpgradeSystem in _tracks():
		system.end_batch()


## Every track a purchase here can move. Read off App rather than listed, so a
## fifth one is batched the day it is added.
func _tracks() -> Array:
	return [_app.upgrade_system, _app.biome_upgrade_system, _app.prestige_upgrade_system,
		_app.geode_upgrade_system]


## Whether spend() would buy anything right now, without buying it. Read-only
## twin of spend(), for the simulator's stride: a stretch of ticks can only be
## skipped while the answer stays no.
##
## Asked only after a tick that bought nothing, which is what lets it be this
## short. Everything spend() buys that is *not* priced in nutrients - a perk, a
## biome upgrade, an automation level - is paid for in a currency that only a
## purchase can move, so it was already unaffordable a tick ago and still is.
## What grows on its own is nutrients, and these are the four things nutrients
## buy.
## What the cheapest of those four costs, or null when the run has nothing left
## it could buy at any price.
##
## Returned as a price rather than a yes/no because every one of these prices is
## frozen for as long as nothing is bought - a cost only moves when a level does
## - so a caller stepping through an idle stretch reads this once and then only
## has to watch its nutrients against it, instead of re-pricing the whole shop
## on every step.
func cheapest_price() -> BigNumber:
	var cheapest: BigNumber = null
	for data: MyceliumNodeData in _app.mycelium_node_data:
		if not data.is_unlocked():
			continue
		cheapest = _lower(cheapest, data.upgrade_cost())
	if _kind == Kind.NODES_ONLY:
		return cheapest

	for id: StringName in _symbiosis_ids:
		var def: UpgradeDef = _app.upgrade_system.def(id)
		if def == null or (def.max_level > 0 and _app.upgrade_system.level(id) >= def.max_level):
			continue
		cheapest = _lower(cheapest, _app.upgrade_system.cost(id))
	for biome: BiomeDef in _app.biomes.biomes:
		if not _app.biomes_data.is_unlocked(biome.key):
			# Only a nutrient-priced gate can open on its own; a crystal-priced
			# one is waiting on an achievement, which ends the stretch anyway.
			if biome.unlock_currency == CurrencyTypes.Types.NUTRIENTS:
				cheapest = _lower(cheapest, biome.unlock_cost)
			continue
		cheapest = _lower(cheapest, _app.biome_size_cost(biome.key))
	return cheapest


func _lower(cheapest: BigNumber, price: BigNumber) -> BigNumber:
	return price if cheapest == null or price.lt(cheapest) else cheapest


# ------------------------------------------------------------------ progression

## The purchases that are not a choice: gates, points, perks and automations.
func _progression() -> int:
	var made := 0
	# Claimed first: the crystals pay for the automations bought further down.
	if _app.has_achievement_claims():
		_app.claim_all_achievements()
		made += 1
	made += _buy_cheapest_automation()
	for def: BiomeDef in _app.biomes.biomes:
		if _app.can_unlock_biome(def.key):
			_app.unlock_biome(def.key)
			made += 1
		if not _app.biomes_data.is_unlocked(def.key):
			continue     # a shut biome has no size to grow and no points to spend
		if _app.can_buy_biome_size(def.key):
			_app.buy_biome_size(def.key)
			made += 1
		made += _spend_biome_points(def.key)
	made += _buy_cheapest_perk()
	return made


## Spends this biome's available points on whatever upgrades have room. Points
## only buy biome upgrades, so an unspent one is wasted.
##
## The budget is read once and counted down locally, per the split BiomeSystem
## documents on has_upgrade_room(): can_buy_upgrade() re-derives the biome's XP
## and resolves &"biome_points" through every upgrade track, and paying that once
## per upgrade id per biome per tick was the most expensive thing in a run.
func _spend_biome_points(key: StringName) -> int:
	var points: int = _app.biome_available_points(key)
	if points < 1:
		return 0
	var made := 0
	for id: StringName in _app.biome_upgrade_ids(key):
		if points < 1:
			break
		if not _app.has_biome_upgrade_room(id, key):
			continue
		if not _app.buy_biome_upgrade(id, key):
			continue
		points -= 1
		made += 1
	return made


## One perk per call, cheapest first, so biomass goes into the shallow end of the
## web before a deep node soaks it all up.
func _buy_cheapest_perk() -> int:
	var best: StringName = &""
	var best_cost: BigNumber = null
	for id: StringName in _app.perk_defs:
		if not _app.can_buy_perk(id):
			continue
		var cost: BigNumber = _app.prestige_upgrade_system.cost(id)
		if best_cost == null or cost.lt(best_cost):
			best = id
			best_cost = cost
	if best.is_empty():
		return 0
	return 1 if _app.buy_perk(best) else 0


## One automation level per call, cheapest first. Crystals buy nothing else, so
## an unspent one is a level the run should already have had.
func _buy_cheapest_automation() -> int:
	var best: StringName = &""
	var best_cost: BigNumber = null
	for def: AutomationDef in _app.automations.automations:
		if not _app.can_buy_automation(def.id):
			continue
		var cost: BigNumber = _app.automation_cost(def.id)
		if best_cost == null or cost.lt(best_cost):
			best = def.id
			best_cost = cost
	if best.is_empty():
		return 0
	return 1 if _app.buy_automation(best) else 0


# --------------------------------------------------------------------- shopping

## The one real decision: which nutrient purchase to make next, if any. Returns
## how many levels it bought, at most `budget`.
##
## Once a winner is picked it is bought in a run rather than one level per scan.
## Its own price and gain are re-read after every level, and the run stops as
## soon as it no longer beats the best *other* candidate from the scan, so the
## sequence of purchases matches the one-at-a-time version wherever it matters.
## What the run does not re-read is the runner-up's gain, which a purchase can
## move - a late tick buying forty levels through forty full scans was the
## second most expensive thing in a run, and this is the half of it that a
## simulated player would not notice.
func _buy_best(budget: int) -> int:
	var candidates := _affordable()
	if candidates.is_empty():
		return 0
	var chosen := 0
	for i in candidates.size():
		if _prefer(candidates[i], candidates[chosen]):
			chosen = i
	var best: Dictionary = candidates[chosen]
	var rival := _runner_up(candidates, chosen)

	var bought := 0
	while bought < budget:
		if not best["buy"].call():
			break
		bought += 1
		var repriced: Dictionary = best["refresh"].call()
		if repriced.is_empty():
			break     # maxed out, or the next level is out of reach
		best["cost"] = repriced["cost"]
		best["gain"] = repriced["gain"]
		if not rival.is_empty() and not _prefer(best, rival):
			break
	return bought


## The best candidate other than the one already chosen, or an empty dictionary
## when there was only one.
func _runner_up(candidates: Array[Dictionary], chosen: int) -> Dictionary:
	var best := -1
	for i in candidates.size():
		if i == chosen:
			continue
		if best < 0 or _prefer(candidates[i], candidates[best]):
			best = i
	return {} if best < 0 else candidates[best]


## Everything buyable with nutrients right now, each with what it costs and a
## rough measure of what it gives back.
##
## The two gains are not in the same unit - a node's is production per tick, an
## upgrade's is the size of its own effect - so ROI only ever compares like with
## like exactly. Across kinds it is a heuristic, and deliberately so: measuring a
## purchase exactly would mean making it and undoing it.
func _affordable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for data: MyceliumNodeData in _app.mycelium_node_data:
		if not data.can_buy_upgrade():
			continue
		out.append({
			"cost": data.upgrade_cost(),
			"gain": _app.node_production_bonus(data.node.id_key),
			"buy": func() -> bool: return data.buy_upgrade(),
			"refresh": func() -> Dictionary: return _node_offer(data),
		})
	if _kind == Kind.NODES_ONLY:
		return out

	for id: StringName in _symbiosis_ids:
		if not _app.upgrade_system.can_buy(id, _app.player_data.nutrients):
			continue
		out.append({
			"cost": _app.upgrade_system.cost(id),
			"gain": _app.upgrade_system.next_level_delta(id, _app.resolve_context),
			"buy": func() -> bool: return _app.upgrade_system.buy(id, _app.player_data),
			"refresh": func() -> Dictionary: return _symbiosis_offer(id),
		})
	return out


## What one candidate costs and gives *now*, or nothing when it is no longer
## worth offering. Lets a run of purchases reprice its winner without rebuilding
## the whole candidate list.
func _node_offer(data: MyceliumNodeData) -> Dictionary:
	if not data.can_buy_upgrade():
		return {}
	return {
		"cost": data.upgrade_cost(),
		"gain": _app.node_production_bonus(data.node.id_key),
	}


func _symbiosis_offer(id: StringName) -> Dictionary:
	if not _app.upgrade_system.can_buy(id, _app.player_data.nutrients):
		return {}
	return {
		"cost": _app.upgrade_system.cost(id),
		"gain": _app.upgrade_system.next_level_delta(id, _app.resolve_context),
	}


func _prefer(candidate: Dictionary, best: Dictionary) -> bool:
	if _kind == Kind.CHEAPEST or _kind == Kind.NODES_ONLY:
		return candidate["cost"].lt(best["cost"])
	return _ratio(candidate).gt(_ratio(best))


## Gain per nutrient. A free purchase would divide by zero, so it is reported as
## its raw gain, which is the largest ratio anything can have.
func _ratio(candidate: Dictionary) -> BigNumber:
	var cost: BigNumber = candidate["cost"]
	if cost.mantissa == 0.0:
		return candidate["gain"]
	return candidate["gain"].div(cost)
