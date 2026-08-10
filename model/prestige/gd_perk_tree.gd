class_name PerkTree
extends RefCounted
## MODEL: pure generator turning a PerkBranchList into the full set of PerkDefs.
## Cost, effects, name and description come straight from the authored
## PerkNodeDefs. Only the position is generated, from node depth and sibling
## count, so branches of any shape work without touching this file.
##
## Authoring points downward: a node lists its children, so parent_id is filled
## in during the walk rather than authored.

const CANVAS_CENTER := 520.0
const ROOT_RADIUS := 150.0
const DEPTH_RADIUS_STEP := 103.0
const SIBLING_SPREAD_DEG := 26.0
const BRANCH_START_DEG := -90.0  ## first branch points straight up from the core

static func build(branch_list: PerkBranchList) -> Array[PerkDef]:
	var seen: Dictionary = {}  # StringName id -> true, across all branches
	var perks: Array[PerkDef] = [_make_core(branch_list.core)]
	seen[branch_list.core.id] = true
	# Branches fan out evenly in list order. Spacing is derived, not authored,
	# so adding or removing a branch can't leave the web lopsided or overlapping.
	var step := 360.0 / float(maxi(1, branch_list.branches.size()))
	for i in branch_list.branches.size():
		var branch: PerkBranchDef = branch_list.branches[i]
		_place_children(branch, branch.roots, branch_list.core.id,
			deg_to_rad(BRANCH_START_DEG + step * float(i)), 0, seen, perks)
	return perks

static func _make_core(core: PerkNodeDef) -> PerkDef:
	var p := PerkDef.new()
	p.id = core.id
	p.branch_key = &""
	p.parent_id = &""
	p.display_name = core.display_name
	p.description = core.description
	p.max_level = core.max_level
	p.base_cost = core.base_cost
	p.cost_growth = core.cost_growth
	p.cost_growth_exponent = core.cost_growth_exponent
	p.effects = core.effects
	p.world_x = CANVAS_CENTER
	p.world_y = CANVAS_CENTER
	return p

static func _place_children(branch: PerkBranchDef, siblings: Array[PerkNodeDef], parent_id: StringName,
		parent_angle: float, depth: int, seen: Dictionary, out: Array[PerkDef]) -> void:
	var spread := deg_to_rad(SIBLING_SPREAD_DEG)
	for i in siblings.size():
		var node: PerkNodeDef = siblings[i]
		if seen.has(node.id):
			push_error("Perk branch '%s' reuses id '%s', skipping that node and everything under it." % [branch.key, node.id])
			continue
		seen[node.id] = true
		var angle := parent_angle + spread * (float(i) - (siblings.size() - 1) / 2.0)
		out.append(_make_perk(branch, node, parent_id, angle, depth))
		_place_children(branch, node.children, node.id, angle, depth + 1, seen, out)

static func _make_perk(branch: PerkBranchDef, node: PerkNodeDef, parent_id: StringName, angle: float, depth: int) -> PerkDef:
	var p := PerkDef.new()
	p.id = node.id
	p.branch_key = branch.key
	p.parent_id = parent_id
	p.display_name = node.display_name
	p.description = node.description
	p.max_level = node.max_level
	p.base_cost = node.base_cost
	p.cost_growth = node.cost_growth
	p.cost_growth_exponent = node.cost_growth_exponent
	p.effects = branch.effects_for(node)
	var r := ROOT_RADIUS + DEPTH_RADIUS_STEP * depth
	p.world_x = CANVAS_CENTER + cos(angle) * r
	p.world_y = CANVAS_CENTER + sin(angle) * r
	return p
