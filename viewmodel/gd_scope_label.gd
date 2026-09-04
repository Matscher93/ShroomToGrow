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
## Scope.NODE addresses tiers, biomes and crystal boosts through the one `target`
## field (see authored_data_test._scope_targets), so all three are looked up
## here: "on Nutrient Flow" is what the Well card has always said, and Bounty's
## perks land a biome point "on Permafrost". "on node boost_nutrients" is not a
## thing the player has ever been shown.
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
