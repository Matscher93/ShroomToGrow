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
