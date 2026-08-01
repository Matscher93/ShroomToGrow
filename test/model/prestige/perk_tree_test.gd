extends GdUnitTestSuite
## Unit tests for PerkTree (model/prestige/gd_perk_tree.gd) — the layout rules,
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
			"Branch '%s' has %d roots — this test assumes one per branch." \
				% [branch.key, branch.roots.size()]).is_equal(1)
		var root: PerkDef = _perks[branch.roots[0].id]
		# Wrapped, so a branch past 180° compares against the same angle the
		# atan2 above reports rather than its unwrapped twin.
		assert_float(wrapf(_angle_of(root) - expected, -PI, PI)) \
			.is_equal_approx(0.0, EPS)
		expected += step

func test_every_branch_root_sits_one_root_radius_from_the_core() -> void:
	for branch in _branches.branches:
		var root: PerkDef = _perks[branch.roots[0].id]
		var offset := Vector2(root.world_x, root.world_y) \
			- Vector2(PerkTree.CANVAS_CENTER, PerkTree.CANVAS_CENTER)
		assert_float(offset.length()).is_equal_approx(PerkTree.ROOT_RADIUS, EPS)
