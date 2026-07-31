class_name PerkTree
extends RefCounted
## MODEL — pure generator: turns a PerkBranchList into the full set of PerkDefs.
## Cost/effect/name/description all come straight from the authored
## PerkNodeDefs; the only thing generated is where each node sits, derived from
## how deep it hangs off the core and how many siblings it shares a parent with.
## Branches can be any shape — chain as long as you like, fork as often as you
## like — without touching this file.
##
## Authoring points downward: a node lists its children, so the parent_id on the
## generated PerkDef is filled in during the walk rather than authored.

const CANVAS_CENTER := 520.0
const ROOT_RADIUS := 150.0
const DEPTH_RADIUS_STEP := 103.0
const SIBLING_SPREAD_DEG := 26.0

static func build(branch_list: PerkBranchList) -> Array[PerkDef]:
	var seen: Dictionary = {}  # StringName id -> true, across every branch
	var perks: Array[PerkDef] = [_make_core(branch_list.core)]
	seen[branch_list.core.id] = true
	for branch in branch_list.branches:
		_place_children(branch, branch.roots, branch_list.core.id,
			deg_to_rad(branch.angle_degrees), 0, seen, perks)
	return perks

static func _make_core(core: PerkNodeDef) -> PerkDef:
	var p := PerkDef.new()
	p.id = core.id
	p.branch_key = &""
	p.parent_id = &""
	p.display_name = core.display_name
	p.description = core.description
	p.max_level = core.max_level
	p.base_cost = BigNumber.from_value(core.base_cost)
	p.cost_growth = core.cost_growth
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
			push_error("Perk branch '%s' reuses id '%s' — skipping that node and everything under it." % [branch.key, node.id])
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
	p.base_cost = BigNumber.from_value(node.base_cost)
	p.cost_growth = node.cost_growth
	p.effects = branch.effects_for(node)
	var r := ROOT_RADIUS + DEPTH_RADIUS_STEP * depth
	p.world_x = CANVAS_CENTER + cos(angle) * r
	p.world_y = CANVAS_CENTER + sin(angle) * r
	return p
