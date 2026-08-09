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
func spend() -> int:
	var bought := 0
	for _attempt in MAX_PURCHASES_PER_TICK:
		var made := _progression() if _kind != Kind.NODES_ONLY else 0
		made += 1 if _buy_best() else 0
		if made == 0:
			break
		bought += made
	return bought


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
		if _app.can_buy_biome_size(def.key):
			_app.buy_biome_size(def.key)
			made += 1
		# Points only buy biome upgrades, so an unspent one is wasted.
		for id: StringName in _app.biome_upgrade_ids(def.key):
			if _app.can_buy_biome_upgrade(id, def.key):
				_app.buy_biome_upgrade(id, def.key)
				made += 1
	made += _buy_cheapest_perk()
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

## The one real decision: which nutrient purchase to make next, if any.
func _buy_best() -> bool:
	var candidates := _affordable()
	if candidates.is_empty():
		return false
	var best: Dictionary = candidates[0]
	for candidate: Dictionary in candidates:
		if _prefer(candidate, best):
			best = candidate
	return best["buy"].call()


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
		})
	return out


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
