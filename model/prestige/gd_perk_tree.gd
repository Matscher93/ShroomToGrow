class_name PerkTree
## MODEL — pure generator: turns a PerkBranchList into the full set of PerkDefs.
## Cost/effect/name/description all come straight from the authored
## PerkNodeDefs; the only thing generated is where each node sits, derived from
## how deep it hangs off the core and how many siblings it shares a parent with.
## Branches can be any shape — chain as long as you like, fork as often as you
## like — without touching this file.

const CANVAS_CENTER := 520.0
const ROOT_RADIUS := 150.0
const DEPTH_RADIUS_STEP := 103.0
const SIBLING_SPREAD_DEG := 26.0

static func build(branch_list: PerkBranchList) -> Array[PerkDef]:
	var perks: Array[PerkDef] = [_make_core(branch_list.core)]
	for branch in branch_list.branches:
		perks.append_array(_build_branch(branch))
	return perks

static func _make_core(core: PerkNodeDef) -> PerkDef:
	var p := PerkDef.new()
	p.id = &"core"
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

static func _build_branch(branch: PerkBranchDef) -> Array[PerkDef]:
	var children_by_parent: Dictionary = {}  # StringName parent_key -> Array[PerkNodeDef]
	var seen: Dictionary = {}
	for node in branch.nodes:
		if seen.has(node.key):
			push_error("Perk branch '%s' has two nodes keyed '%s' — skipping the second." % [branch.key, node.key])
			continue
		seen[node.key] = true
		if not children_by_parent.has(node.parent_key):
			children_by_parent[node.parent_key] = []
		children_by_parent[node.parent_key].append(node)

	for parent_key in children_by_parent:
		if parent_key != &"" and not seen.has(parent_key):
			push_error("Perk branch '%s': parent '%s' does not exist — its children are unreachable." % [branch.key, parent_key])

	var perks: Array[PerkDef] = []
	_place_children(branch, children_by_parent, &"", &"core", deg_to_rad(branch.angle_degrees), 0, perks)
	return perks

static func _place_children(branch: PerkBranchDef, children_by_parent: Dictionary, parent_key: StringName,
		parent_id: StringName, parent_angle: float, depth: int, out: Array[PerkDef]) -> void:
	var siblings: Array = children_by_parent.get(parent_key, [])
	var spread := deg_to_rad(SIBLING_SPREAD_DEG)
	for i in siblings.size():
		var node: PerkNodeDef = siblings[i]
		var angle := parent_angle + spread * (float(i) - (siblings.size() - 1) / 2.0)
		out.append(_make_perk(branch, node, parent_id, angle, depth))
		_place_children(branch, children_by_parent, node.key, _perk_id(branch, node), angle, depth + 1, out)

static func _make_perk(branch: PerkBranchDef, node: PerkNodeDef, parent_id: StringName, angle: float, depth: int) -> PerkDef:
	var p := PerkDef.new()
	p.id = _perk_id(branch, node)
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

static func _perk_id(branch: PerkBranchDef, node: PerkNodeDef) -> StringName:
	return StringName("%s%s" % [branch.key, node.key])
