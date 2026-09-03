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
## The innermost ring is where two branches come closest: sibling spacing is an
## angle, so the arc it buys is smallest where the radius is. Raised from 150
## when Substrate grew a potency and a synergy leaf on every rung - those sit at
## the very edge of Substrate's slice, and at 150 the depth-1 leaf's label landed
## on Dominion's. perk_node_test.gd is what pins that down; 190 is where it
## starts passing, so this leaves a ring's worth of margin.
const ROOT_RADIUS := 200.0
## Node circles are 40px and the label block under one is about 60px tall, so a
## step much under this puts a node's labels on top of whatever the next ring
## over happens to sit beneath it. perk_node_test.gd is what pins that down.
##
## Raised from 140 when Dominion made an eighth branch. A branch's sibling spread
## is capped by its slice of the circle (see _spread_for), so each new branch
## narrows every existing one; the arc between two siblings is that angle times
## the radius, and the radius is the only half of that product a new branch does
## not shrink. Widening BRANCH_SLICE_FILL instead would buy the same angle back
## by eating the gutter, which pushes neighbouring *branches* into each other -
## measurably worse than what it fixes.
const DEPTH_RADIUS_STEP := 170.0
const SIBLING_SPREAD_DEG := 26.0
## How hard sibling spacing narrows as a branch reaches outward. Spacing is an
## angle, so the arc it buys is the angle times the radius: at a flat 26 degrees
## the tenth ring's siblings sit ten times further apart than the first's, and a
## long branch reads as a fan rather than a line. Scaling the angle by
## (root radius / this ring's radius) to this power pulls that back - 1.0 holds
## the gap between siblings exactly constant the whole way out, 0.0 is the flat
## spacing this replaced, and in between the gap still opens up, just slowly.
##
## 0.5 is where perk_node_test still passes: at 0.75 Tide folds in on itself
## (tide_depth's label lands on tide_shrine) and at 1.0 five more pairs go with
## it. Going tighter than this means giving those branches more room radially,
## not less room angularly.
const SPREAD_FALLOFF := 0.5
const BRANCH_START_DEG := -90.0  ## first branch points straight up from the core
## Fraction of its slice of the circle a branch may fill. The rest is the gutter
## that keeps neighbouring branches from touching.
const BRANCH_SLICE_FILL := 0.8

static func build(branch_list: PerkBranchList) -> Array[PerkDef]:
	var seen: Dictionary = {}  # StringName id -> true, across all branches
	var perks: Array[PerkDef] = [_make_core(branch_list.core)]
	seen[branch_list.core.id] = true
	# Branches fan out evenly in list order. Spacing is derived, not authored,
	# so adding or removing a branch can't leave the web lopsided or overlapping.
	var step := 360.0 / float(maxi(1, branch_list.branches.size()))
	var half_slice := deg_to_rad(step * 0.5 * BRANCH_SLICE_FILL)
	for i in branch_list.branches.size():
		var branch: PerkBranchDef = branch_list.branches[i]
		_place_children(branch, branch.roots, branch_list.core.id,
			deg_to_rad(BRANCH_START_DEG + step * float(i)), 0,
			_spread_for(branch, half_slice), seen, perks)
	return perks

## Sibling spacing for one branch, shrunk if the branch is wide enough to spill
## out of its slice. A node's angle is its branch's centre line plus the spacing
## times the sibling offsets accumulated down to it, so the largest offset in the
## branch is what decides the largest spacing that still fits.
static func _spread_for(branch: PerkBranchDef, half_slice: float) -> float:
	var spread := deg_to_rad(SIBLING_SPREAD_DEG)
	var widest := _widest_offset(branch.roots, 0.0)
	return spread if widest <= 0.0 else minf(spread, half_slice / widest)

## What one ring's sibling step is worth against a root's, per SPREAD_FALLOFF.
## 1.0 at the root ring, and smaller the further out a ring sits.
static func _depth_falloff(depth: int) -> float:
	if SPREAD_FALLOFF <= 0.0:
		return 1.0
	return pow(ROOT_RADIUS / (ROOT_RADIUS + DEPTH_RADIUS_STEP * float(depth)), SPREAD_FALLOFF)

## Offsets are counted in root-ring steps, so an offset picked up out at depth
## eight counts for a fraction of one picked up at depth one - the same weighting
## _place_children lays the branch out with. Without it the cap would be measured
## against a spread the branch no longer uses and would shrink every long branch
## for angles it never reaches.
static func _widest_offset(siblings: Array[PerkNodeDef], parent_offset: float, depth: int = 0) -> float:
	var widest := absf(parent_offset)
	var falloff := _depth_falloff(depth)
	for i in siblings.size():
		var offset := parent_offset + (float(i) - (siblings.size() - 1) / 2.0) * falloff
		widest = maxf(widest, _widest_offset(siblings[i].children, offset, depth + 1))
	return widest

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
		parent_angle: float, depth: int, spread: float, seen: Dictionary, out: Array[PerkDef]) -> void:
	for i in siblings.size():
		var node: PerkNodeDef = siblings[i]
		if seen.has(node.id):
			push_error("Perk branch '%s' reuses id '%s', skipping that node and everything under it." % [branch.key, node.id])
			continue
		seen[node.id] = true
		var angle := parent_angle + spread * (float(i) - (siblings.size() - 1) / 2.0) * _depth_falloff(depth)
		out.append(_make_perk(branch, node, parent_id, angle, depth))
		_place_children(branch, node.children, node.id, angle, depth + 1, spread, seen, out)

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
