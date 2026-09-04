extends GdUnitTestSuite
## Every authored description checked against the effect it describes.
##
## A description and its effect are two spellings of one number. Before the
## {token} mechanism they were authored separately and drifted in silence - seven
## Well boons were quoting rates their effects had not had for some time, with no
## load error, no warning and nothing on screen to say the card was wrong.
##
## Its own suite rather than a section of authored_data_test, because that file
## stops executing partway through: a failing perk-cost assertion aborts the run
## and everything after it is never reached. A guard that only runs while the
## rest of the data is healthy is not a guard.

var _perks: Array[PerkDef]
var _symbiosis_defs: Array[UpgradeDef]
var _biome_defs: Array[UpgradeDef]
var _projects: Array[ProjectDef]
var _mission_boosts: Array[MissionBoostDef]

func before_test() -> void:
	_perks = PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList)
	_symbiosis_defs = UpgradeDefLoader.load_all(UpgradeDefLoader.SYMBIOSIS_PATH)
	_biome_defs = UpgradeDefLoader.load_all(UpgradeDefLoader.BIOME_PATH)
	_projects = (load("res://data/well/all_projects.tres") as ProjectList).projects
	_mission_boosts = (load("res://data/ruins/all_mission_boosts.tres") as MissionBoostList).boosts

## Every track that reaches a card through an UpgradeDef. Mirrors
## authored_data_test._all_upgrade_defs(); the Ruins ladder's defs are generated
## from the boost list but their effects are authored verbatim.
func _all_upgrade_defs() -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	defs.append_array(_symbiosis_defs)
	defs.append_array(_biome_defs)
	for perk in _perks:
		defs.append(perk)
	var list := MissionBoostList.new()
	list.boosts = _mission_boosts
	defs.append_array(MissionBoostTree.build(list))
	return defs

## Guards every sweep below: an empty registry would pass all of them without
## checking anything.
func test_every_registry_loads_something() -> void:
	assert_array(_all_upgrade_defs()).is_not_empty()
	assert_array(_projects).is_not_empty()

## Every authored description in the game paired with the effects behind it, as
## {"where", "text", "effects", "max_level"}.
##
## The pairing is the whole point: a description is only checkable against the
## numbers it is describing, and the tracks keep them in different places - a
## sibling .tres for a biome upgrade, a sub-resource for a Well boon, an array
## on the def for a perk.
func _described() -> Array[Dictionary]:
	var described: Array[Dictionary] = []
	for def in _all_upgrade_defs():
		# Through the same lookup the panel uses, so a cap perk's {max_level_step}
		# resolves here exactly as it does on screen. Every other track's extras
		# are its own live numbers rather than authored ones, so the sweep asks for
		# none: a description leaning on them has to say so by naming the token.
		described.append({"where": "upgrade '%s'" % def.id, "text": def.description,
			"effects": def.effects, "max_level": def.max_level,
			"extras": PerkTree.cap_step_extras(def.id)})
	for def in _projects:
		var boon_effects: Array = []
		for boon in def.boons:
			boon_effects.append(boon.effect)
			described.append({"where": "project '%s' boon '%s'" % [def.id, boon.display_name],
				"text": boon.description, "effects": [boon.effect], "max_level": 0,
				"extras": {}})
		described.append({"where": "project '%s'" % def.id, "text": def.description,
			"effects": boon_effects, "max_level": def.max_level, "extras": {}})
	return described

## The check this whole mechanism exists for: a number the effect already holds
## must never be typed into the sentence beside it.
##
## Typed rather than pattern-matched, because a pattern cannot tell a magnitude
## from a tier: "Step 9 of Rot Grub's chain" and "Opens Level 10 nodes" are
## authored numbers that no effect knows, and are meant to stay written out. What
## is banned is the exact string expand() would have produced - which is what a
## retune silently leaves behind.
func test_no_description_hardcodes_a_value_its_effect_already_holds() -> void:
	for entry in _described():
		# Scanned with the tokens taken out: a {value:3} carries a digit of its own,
		# and an index is not a magnitude anybody typed.
		var text := _without_tokens(entry["text"])
		if text.is_empty():
			continue
		for effect: UpgradeEffectDef in entry["effects"]:
			if effect == null:
				continue
			for token: String in ["{value}", "{magnitude}", "{cap}", "{total}"]:
				var rendered := EffectLabel.expand(token, [effect], int(entry["max_level"]))
				if rendered.is_empty():
					continue
				assert_bool(text.contains(rendered)) \
					.override_failure_message(("%s writes '%s' into its description, " \
						+ "which is what %s already resolves to. Use the token, or the two " \
						+ "drift apart the next time the effect is retuned.\n  %s") \
						% [entry["where"], rendered, token, text]).is_false()

## A number formatted the way an effect's op formats one, sitting in a sentence
## that names no token, is a value that has already drifted - it no longer
## matches, which is why the check above did not catch it.
##
## Deliberately narrow: only the shapes EffectLabel produces (a x1.045, a signed
## percentage, a signed decimal with a unit), so an ordinal in prose is left
## alone.
func test_no_description_carries_a_stale_effect_number() -> void:
	var stale := RegEx.new()
	stale.compile("(x1\\.\\d|[-+]\\d+(\\.\\d+)?s\\b|[-+]\\d+(\\.\\d+)?%)")
	for entry in _described():
		var text := _without_tokens(entry["text"])
		if text.is_empty() or entry["effects"].is_empty():
			continue
		assert_bool(stale.search(text) != null) \
			.override_failure_message(("%s carries a hand-written effect number that no " \
				+ "longer matches its effect, so nothing replaced it.\n  %s") \
				% [entry["where"], text]).is_false()

## A typo'd token renders as itself rather than as a number, so the card ships
## saying "{valeu}". Cheap to catch here, invisible until a screenshot otherwise.
func test_every_token_in_every_description_resolves() -> void:
	for entry in _described():
		var unresolved := EffectLabel.unresolved_tokens(entry["text"], entry["effects"],
			int(entry["max_level"]), entry["extras"])
		assert_int(unresolved.size()) \
			.override_failure_message("%s names %s, which nothing resolves.\n  %s" \
				% [entry["where"], " ".join(unresolved), entry["text"]]).is_zero()

## {noun} falls back to the StatResources bucket, which is the right grouping for
## a breakdown and the wrong word for a sentence - a &"crystal_gain" boon would
## read "crystals" where its card said "crystals from achievements". A stat added
## without a noun degrades quietly, so the set is asserted whole.
func test_every_stat_is_worded_for_a_sentence() -> void:
	for stat: StringName in StatNames.ALL:
		assert_bool(EffectLabel.NOUNS.has(stat)) \
			.override_failure_message(("Stat '%s' has no noun in EffectLabel.NOUNS, so a " \
				+ "description naming it falls back to its resource bucket.") % stat).is_true()

## A description with every {token} taken out, so a sweep for hand-typed numbers
## reads only the prose an author actually wrote.
func _without_tokens(text: String) -> String:
	var tokens := RegEx.new()
	tokens.compile(EffectLabel.TOKEN_PATTERN)
	return tokens.sub(text, "", true)

## A perk that carries its own effect has to say what that effect is worth.
##
## The panel shows the authored description when there is one and generates the
## effect line only when there is not, so a perk with a line of pure flavour
## shows the flavour and never the number. Fruiting and Bounty sat like that -
## twelve perks reading "kept through every sporation", with the +25% biomass and
## the +1 biome point nowhere on the screen.
##
## Only perks with an effect of their own: Reach and Instinct's unlock rungs
## inherit their branch's default and their description *is* the whole effect
## ("Opens Level 8 nodes"), which is exactly right and names no number.
func test_every_perk_with_its_own_effect_says_what_a_level_buys() -> void:
	for branch in _branches():
		for node: PerkNodeDef in _walk(branch.roots):
			if node.effects.is_empty():
				continue   # inherits the branch default; its description is the effect
			if node.description.is_empty():
				continue   # no description at all, so the panel generates the line
			assert_bool(node.description.contains("{")) \
				.override_failure_message(("Perk '%s' has an effect of its own but its " \
					+ "description names no token, so the panel shows this and never the " \
					+ "number:\n  %s") % [node.display_name, node.description]).is_true()

func _branches() -> Array[PerkBranchDef]:
	return (load("res://data/prestige/all_branches.tres") as PerkBranchList).branches

## Every authored node in a branch, roots first. PerkTree walks the same children
## lists to build the tree; this walks them to read what was written.
func _walk(nodes: Array[PerkNodeDef]) -> Array[PerkNodeDef]:
	var all: Array[PerkNodeDef] = []
	for node in nodes:
		all.append(node)
		all.append_array(_walk(node.children))
	return all
