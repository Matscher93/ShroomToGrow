extends GdUnitTestSuite
## Unit tests for PerkTree (model/prestige/gd_perk_tree.gd): the layout rules,
## checked against the real authored branches.

const EPS := 0.0001

var _branches: PerkBranchList
var _perks: Dictionary  # StringName -> PerkDef

func before_test() -> void:
	_branches = load("res://data/prestige/all_branches.tres") as PerkBranchList
	_perks = {}
	for perk in PerkTree.build(_branches):
		_perks[perk.id] = perk

func _angle_of(perk: PerkDef) -> float:
	return atan2(perk.world_y - PerkTree.CANVAS_CENTER, perk.world_x - PerkTree.CANVAS_CENTER)

func test_branches_are_spread_evenly_around_the_core() -> void:
	var step := deg_to_rad(360.0 / float(_branches.branches.size()))
	var expected := deg_to_rad(PerkTree.BRANCH_START_DEG)
	for branch in _branches.branches:
		assert_int(branch.roots.size()).override_failure_message(
			"Branch '%s' has %d roots, this test assumes one per branch." \
				% [branch.key, branch.roots.size()]).is_equal(1)
		var root: PerkDef = _perks[branch.roots[0].id]
		# Wrapped so a branch past 180 degrees compares against the angle
		# atan2 reports rather than its unwrapped twin.
		assert_float(wrapf(_angle_of(root) - expected, -PI, PI)) \
			.is_equal_approx(0.0, EPS)
		expected += step

func test_no_branch_reaches_out_of_its_own_slice() -> void:
	var step := 360.0 / float(_branches.branches.size())
	var limit := deg_to_rad(step * 0.5 * PerkTree.BRANCH_SLICE_FILL)
	var centre := deg_to_rad(PerkTree.BRANCH_START_DEG)
	for branch in _branches.branches:
		for perk in _perks.values():
			if perk.branch_key != branch.key:
				continue
			var offset := wrapf(_angle_of(perk) - centre, -PI, PI)
			assert_float(absf(offset)).override_failure_message(
				"Perk '%s' sits %.1f degrees off the '%s' centre line, past the %.1f allowed." \
					% [perk.id, rad_to_deg(absf(offset)), branch.key, rad_to_deg(limit)]) \
				.is_less_equal(limit + EPS)
		centre += deg_to_rad(step)

func test_pricing_is_carried_over_from_the_authored_node() -> void:
	var node := PerkNodeDef.new()
	node.id = &"steep"
	node.max_level = 3
	node.base_cost = BigNumber.new(2.0, 0)
	node.cost_growth = 3.0
	node.cost_growth_exponent = 2.0

	var branch := PerkBranchDef.new()
	branch.key = &"test"
	branch.roots = [node]

	var core := PerkNodeDef.new()
	core.id = &"test_core"
	core.cost_growth_exponent = 1.5

	var list := PerkBranchList.new()
	list.core = core
	list.branches = [branch]

	var built := {}
	for perk in PerkTree.build(list):
		built[perk.id] = perk

	assert_float(built[&"test_core"].cost_growth_exponent).is_equal_approx(1.5, EPS)
	assert_float(built[&"steep"].cost_growth).is_equal_approx(3.0, EPS)
	assert_float(built[&"steep"].cost_growth_exponent).is_equal_approx(2.0, EPS)

	# level * exponent^level in the exponent, so level 2 costs base * 3^(2*2^2), not base * 3^2.
	var system := UpgradeSystem.new()
	system.register(built[&"steep"])
	system.from_save({"steep": 2})
	assert_float(system.cost(&"steep").to_float()).is_equal_approx(2.0 * pow(3.0, 8.0), EPS)

func test_every_branch_root_sits_one_root_radius_from_the_core() -> void:
	for branch in _branches.branches:
		var root: PerkDef = _perks[branch.roots[0].id]
		var offset := Vector2(root.world_x, root.world_y) \
			- Vector2(PerkTree.CANVAS_CENTER, PerkTree.CANVAS_CENTER)
		assert_float(offset.length()).is_equal_approx(PerkTree.ROOT_RADIUS, EPS)


# ─── Reach's Attunement ladder ───────────────────────────────────────────────

## Reach's lowest and highest rungs, which the Attunement pairing spans.
const REACH_FIRST := 4
const REACH_LAST := 10

## Every rung of Reach carries an Attunement, and each one hangs off its own
## rung rather than off the Attunement below it. That is what makes a Level Point
## perk something the ladder hands out as it is climbed, instead of a second
## chain a player could run up without ever reaching further.
func test_every_reach_rung_has_an_attunement_hanging_off_it() -> void:
	for tier in range(REACH_FIRST, REACH_LAST + 1):
		var id := StringName("reach_attunement_%d" % tier)
		assert_bool(_perks.has(id)).override_failure_message(
			"Reach %d has no Attunement beside it." % tier).is_true()
		var perk: PerkDef = _perks[id]
		assert_str(String(perk.parent_id)).override_failure_message(
			"'%s' hangs off '%s', not off its own Reach rung." % [id, perk.parent_id]
			).is_equal("reach_%d" % tier)

func test_every_attunement_grants_level_points() -> void:
	for tier in range(REACH_FIRST, REACH_LAST + 1):
		var perk: PerkDef = _perks[StringName("reach_attunement_%d" % tier)]
		assert_int(perk.effects.size()).override_failure_message(
			"Attunement %d has no effect, so it hands out nothing." % tier).is_equal(1)
		var effect: UpgradeEffectDef = perk.effects[0]
		assert_str(String(effect.stat)).is_equal("level_points")
		assert_int(effect.op).is_equal(UpgradeEffectDef.Op.ADD)
		assert_float(effect.per_level).is_greater(0.0)

## An Attunement never outprices the rung above it, so reaching further always
## stays the cheaper of the two things newly in reach.
func test_each_attunement_is_cheaper_than_the_next_reach_rung() -> void:
	for tier in range(REACH_FIRST, REACH_LAST):
		var attunement: PerkDef = _perks[StringName("reach_attunement_%d" % tier)]
		var next_rung: PerkDef = _perks[StringName("reach_%d" % (tier + 1))]
		assert_bool(attunement.base_cost.lt(next_rung.base_cost)).override_failure_message(
			"Attunement %d costs %s, more than Reach %d's %s." \
				% [tier, attunement.base_cost, tier + 1, next_rung.base_cost]).is_true()

## The chain alternates which side each Attunement takes, which is what keeps
## PerkTree's sibling spread wide enough to lay the branch out - see the comment
## at the top of res_branch_reach.tres. Hanging them all on one side crushed the
## spread from 26 degrees to under 7.
func test_the_reach_chain_stays_near_its_centre_line() -> void:
	var widest := PerkTree._widest_offset(_reach_branch().roots, 0.0)
	assert_float(widest).override_failure_message(
		"Reach's widest sibling offset is %f; past 1.5 the branch stops fitting its slice." \
			% widest).is_less_equal(1.5)

func _reach_branch() -> PerkBranchDef:
	for branch in _branches.branches:
		if branch.key == &"rch":
			return branch
	return null
