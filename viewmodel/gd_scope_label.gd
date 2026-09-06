class_name ScopeLabel
extends RefCounted
## VIEWMODEL: a scope - a bucket key, or an effect's scope and target - as
## something the player has read before.
##
## Lives here rather than under model/ because it is presentation: the model files
## a contribution under "n:7" or "t:canopy" and has no opinion about what to call
## it. Reads the node and boost registries, which are static resources loaded
## once, not game state.
##
## One place, because there were about to be three: the statistics overlay names a
## scope on every bonus row, a generated perk description names one, and a scoped
## biome upgrade names one. Three spellings of "n:7" would have been three
## different words for the same tier.

## The node's own name, as the node panel says it. Falls back to the raw id, so a
## target that no longer names a tier reads as a mistake rather than as nothing.
##
## Scope.NODE addresses tiers, biomes, crystal boosts and farms through the one
## `target` field (see authored_data_test._scope_targets), so all four are looked
## up here: "on Nutrient Flow" is what the Well card has always said, and Bounty's
## perks land a biome point "on Permafrost". "on node boost_nutrients" is not a
## thing the player has ever been shown.
##
## The farms are here because a mission reward targets one - an expedition that
## pays "+20% mission payout on Tap the Seeps" was reading "on node
## farm_tap_the_seeps" on the hero card, which is the id and not a name.
static func node_name(node_id: String) -> String:
	for node in _nodes():
		if str(node.node_id) == node_id:
			return node.name
	for biome in _biomes():
		if String(biome.key) == node_id:
			return biome.display_name
	for boost in _boosts():
		if String(boost.id) == node_id:
			return boost.display_name
	for mission in _missions():
		if String(mission.id) == node_id:
			return mission.display_name
	return "node %s" % node_id

## The registries by path rather than through App.
##
## The same resources App holds - load() is cached by path, so this is that one
## instance and not a second copy - but reachable without the autoload. The
## balance editor's CLI runs with `-s`, where no autoload exists and a bare `App`
## does not even compile, and it needs to word a description exactly the way the
## game does. A registry that is static anyway has no business needing the
## running game to be readable.
static func _nodes() -> Array[MyceliumNode]:
	return (load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes) \
		.mycelium_nodes

static func _biomes() -> Array[BiomeDef]:
	return (load("res://data/biomes/all_biomes.tres") as BiomeList).biomes

static func _boosts() -> Array[BoostDef]:
	return (load("res://data/boosts/all_boosts.tres") as BoostList).boosts

static func _missions() -> Array[MissionDef]:
	return (load("res://data/ruins/all_missions.tres") as MissionList).missions

## A group as a name. Tags are authored lowercase and read as words, so the only
## work here is making one look like a name in a sentence.
static func tag_name(tag: String) -> String:
	return tag.capitalize()

## The scope key as something readable, and "" for a global one - most effects
## are global and repeating "global" on every row is noise.
##
## A node key is turned back into the node's own name: "n:7" is the key the
## bucket is filed under, not something the player has ever seen. A tag key is
## the group's name for the same reason.
static func of_key(key: String) -> String:
	if key.begins_with("n:"):
		return node_name(key.substr(2))
	if key.begins_with("t:"):
		return tag_name(key.substr(2))
	return ""

## One authored effect's scope, named. The same answer as of_key() on the bucket
## that effect writes into, for callers holding the def rather than the key.
static func of_effect(effect: UpgradeEffectDef) -> String:
	match effect.scope:
		UpgradeEffectDef.Scope.NODE:
			return node_name(String(effect.target))
		UpgradeEffectDef.Scope.TAG:
			return tag_name(String(effect.target))
		_:
			return ""

## The scope every one of these effects shares, or "" when they differ or are
## global.
##
## Ten node-scoped copies of one upgrade are ten separate defs with one display
## name between them, so a column of "Mycelium Potency" repeated ten times is
## what a reader gets otherwise. Where the scope is the only thing telling them
## apart, it belongs in the name.
static func of_effects(effects: Array) -> String:
	var shared := ""
	for effect: UpgradeEffectDef in effects:
		var scope := of_effect(effect)
		if scope.is_empty():
			return ""
		if shared.is_empty():
			shared = scope
		elif shared != scope:
			return ""
	return shared

## of_effects() over breakdown rows, which carry the resolved bucket key rather
## than the def it came from.
static func of_keys(effects: Array) -> String:
	var shared := ""
	for effect: Dictionary in effects:
		var scope := of_key(String(effect["key"]))
		if scope.is_empty():
			return ""
		if shared.is_empty():
			shared = scope
		elif shared != scope:
			return ""
	return shared

## A named scope as a phrase to hang off the end of a sentence, and "" for a
## global one so the sentence is left exactly as it was.
static func suffix(scope: String) -> String:
	return "" if scope.is_empty() else " on %s" % scope

# --- Reach ------------------------------------------------------------------

## The stats ProductionSystem resolves per node (see its stack() calls), so a
## GLOBAL effect on one of them reaches every node and that is worth a sentence.
## Every other stat is global in a way the player has no node-shaped picture of:
## "all nodes" on a tick_rate perk would be a promise about the wrong thing.
const NODE_STATS: Array[StringName] = [
	&"node_production", &"potency_production", &"synergy_production",
]

## The word "Level" on a card is the tier's position counting from one -
## res_node_l7.tres is Grove and the Reach perk that opens it says "Level 8
## nodes (Grove)". node_id counts from zero, so every phrase built here has to
## add one; scope_label_test pins it, because an off-by-one is invisible in the
## code and mislabels every card at once.
const LEVEL_OFFSET := 1

## One node tier as the card names it: "Sporocarp (Level 4)". "" for an id that
## is not a node - a biome key or a boost id goes through node_name() instead,
## which is what the caller falls back to.
static func node_phrase(node_id: String) -> String:
	for node in _nodes():
		if String(node.id_key) == node_id:
			return "%s (Level %d)" % [node.name, node.node_id + LEVEL_OFFSET]
	return ""

## What a set of effects reaches, as a phrase: "all nodes", "Sporocarp (Level
## 4)", "Rhizomorph (Level 2) and Colony (Level 5)", or a mix of the two shapes.
## "" when there is nothing worth saying - a tick_rate perk reaches the whole
## game, and "affects everything" is not information.
##
## Generated rather than authored, because the alternative is what the data used
## to do: eighteen descriptions typing "on every node" by hand, a Well project
## spanning three tiers naming none of them, and two biome upgrades saying it
## twice. One reader of the effects cannot drift from them.
static func reach(effects: Array) -> String:
	var state := _new_reach_state()
	for effect: UpgradeEffectDef in effects:
		if effect == null:
			continue
		_collect(effect.scope, String(effect.target), effect.stat, state)
	return _reach_text(state)

## reach() for a scope that has no UpgradeEffectDef behind it yet. BoostSystem
## generates one def per tier and rewrites its rate as the ladder climbs, so the
## card holds the BoostDef's own scope/target/stat and nothing to hand reach().
static func reach_of(scope: int, target: StringName, stat: StringName) -> String:
	var state := _new_reach_state()
	_collect(scope, String(target), stat, state)
	return _reach_text(state)

## reach() as the standalone line a card appends under its description, and ""
## for effects with no reach to state - the caller appends nothing rather than
## an empty line.
static func reach_sentence(effects: Array) -> String:
	return sentence(reach(effects))

## A reach phrase as that line. Separate from reach_sentence() so a caller
## holding a phrase from reach_of() words it the same way.
static func sentence(phrase: String) -> String:
	return "" if phrase.is_empty() else "Affects %s." % phrase

static func _new_reach_state() -> Dictionary:
	return {"all_nodes": false, "tiers": [], "others": PackedStringArray()}

## One effect's reach, folded into the running state.
##
## The tiers are collected as node ids rather than as finished phrases so they
## can be sorted by position: a Well project's boons are authored in funding
## order, and "Colony (Level 5) and Rhizomorph (Level 2)" reads as a list nobody
## put in order. Everything else keeps its authored order, which is the order the
## card lists the boons in.
static func _collect(scope: int, target: String, stat: StringName, state: Dictionary) -> void:
	match scope:
		UpgradeEffectDef.Scope.GLOBAL:
			if NODE_STATS.has(stat):
				state["all_nodes"] = true
		UpgradeEffectDef.Scope.TAG:
			_add_other(state, tag_name(target))
		UpgradeEffectDef.Scope.NODE:
			var tier := _node_id(target)
			if tier < 0:
				_add_other(state, node_name(target))
			elif not state["tiers"].has(tier):
				state["tiers"].append(tier)

static func _add_other(state: Dictionary, name: String) -> void:
	var others: PackedStringArray = state["others"]
	if not others.has(name):
		others.append(name)
		state["others"] = others

## `target` as a node_id, and -1 for a target that names something else - a
## biome, a boost, a farm. Read off the registry rather than by parsing digits,
## so an id that is not a tier cannot pick up a level number it has no business
## having.
static func _node_id(target: String) -> int:
	for node in _nodes():
		if String(node.id_key) == target:
			return node.node_id
	return -1

static func _reach_text(state: Dictionary) -> String:
	var tiers: Array = state["tiers"]
	tiers.sort()
	var parts: PackedStringArray = []
	for tier: int in tiers:
		parts.append(node_phrase(str(tier)))
	parts.append_array(state["others"])
	var named := _join(parts)
	if not state["all_nodes"]:
		return named
	# A Well project usually raises every node and then a few tiers again. Saying
	# only "all nodes" would hide the tiers it was funded for; listing only the
	# tiers would hide the rest of its payout.
	return "all nodes" if named.is_empty() else "all nodes, with extra on %s" % named

static func _join(parts: PackedStringArray) -> String:
	if parts.size() <= 1:
		return "" if parts.is_empty() else parts[0]
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]
