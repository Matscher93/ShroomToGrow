class_name PerkTree
## MODEL — pure generator: turns a PerkBranchList into the full set of
## PerkDefs (positions, ids, parent links). Every branch gets the same
## fixed shape — core -> I -> II -> {III·A, III·B} -> IV·A / IV·B — so
## adding a branch later is authoring data, not writing code.

const CANVAS_CENTER := 520.0
const RADII: Array[float] = [150.0, 250.0, 355.0, 460.0]  # index = tier
const FORK_SPREAD_DEG := 13.0
const TIER_COSTS: Array[float] = [2.0, 4.0, 8.0, 16.0]
const ROMAN: Array[String] = ["I", "II", "III", "IV"]
const MAX_PERK_LEVEL := 5
const COST_GROWTH := 1.6

static func build(branch_list: PerkBranchList) -> Array[PerkDef]:
	var perks: Array[PerkDef] = [_make_core()]
	for branch in branch_list.branches:
		perks.append_array(_build_branch(branch))
	return perks

static func _make_core() -> PerkDef:
	var p := PerkDef.new()
	p.id = &"core"
	p.branch_key = &""
	p.parent_id = &""
	p.display_name = "Sporation"
	p.description = "The first bloom. Every arm of the mycelial web grows outward from here."
	p.max_level = 1
	p.base_cost = BigNumber.from_value(1.0)
	p.cost_growth = COST_GROWTH
	p.world_x = CANVAS_CENTER
	p.world_y = CANVAS_CENTER
	return p

static func _build_branch(branch: PerkBranchDef) -> Array[PerkDef]:
	var angle := deg_to_rad(branch.angle_degrees)
	var spread := deg_to_rad(FORK_SPREAD_DEG)
	var p1 := _make_tier(branch, 0, angle, &"core", "")
	var p2 := _make_tier(branch, 1, angle, p1.id, "")
	var p3a := _make_tier(branch, 2, angle - spread, p2.id, "·A")
	var p3b := _make_tier(branch, 2, angle + spread, p2.id, "·B")
	var p4a := _make_tier(branch, 3, angle - spread * 1.5, p3a.id, "·A")
	var p4b := _make_tier(branch, 3, angle + spread * 1.5, p3b.id, "·B")
	return [p1, p2, p3a, p3b, p4a, p4b]

static func _make_tier(branch: PerkBranchDef, tier: int, angle: float, parent_id: StringName, suffix: String) -> PerkDef:
	var p := PerkDef.new()
	p.id = StringName("%s%s%s" % [branch.key, ROMAN[tier], suffix])
	p.branch_key = branch.key
	p.parent_id = parent_id
	p.display_name = "%s %s%s" % [branch.label, ROMAN[tier], suffix]
	p.description = "%s node — kept through every sporation." % branch.label
	p.max_level = MAX_PERK_LEVEL
	p.base_cost = BigNumber.from_value(TIER_COSTS[tier])
	p.cost_growth = COST_GROWTH
	p.effects = [branch.effect]
	var r := RADII[tier]
	p.world_x = CANVAS_CENTER + cos(angle) * r
	p.world_y = CANVAS_CENTER + sin(angle) * r
	return p
