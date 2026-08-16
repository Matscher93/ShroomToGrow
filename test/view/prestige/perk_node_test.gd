extends GdUnitTestSuite
## Label footprints in the mycelial web, measured off the real scene at the real
## world positions PerkTree hands out.
##
## Measured rather than asserted against a constant on purpose: a wider font, a
## bigger font size, a longer authored perk name and a tighter layout radius all
## break the same way - two labels drawn on top of each other - and only a real
## instantiated node catches all four.

const NODE_SCENE := "res://view/prestige/sc_perk_node.tscn"

var _rects: Array[Rect2] = []
var _ids: Array[StringName] = []

func before_test() -> void:
	_rects = []
	_ids = []

## The labels of a node, in world space, as one rect. PerkWeb offsets a node by
## half NODE_SIZE so the circle centres on the perk's world position, so the
## label block has to be offset the same way to land where the player sees it.
func _label_rect(node: PerkNode, def: PerkDef) -> Rect2:
	var origin := Vector2(def.world_x, def.world_y) - Vector2(PerkWeb.NODE_SIZE, PerkWeb.NODE_SIZE) / 2.0
	var block := node.name_label.get_global_rect().merge(node.level_label.get_global_rect())
	# Global to node-local, then node-local to world: the holder these are parented
	# to for measuring is not where the web puts them.
	return Rect2(origin + block.position - node.get_global_rect().position, block.size)

func _build_all() -> void:
	var branches: PerkBranchList = load("res://data/prestige/all_branches.tres")
	var packed: PackedScene = load(NODE_SCENE)
	var holder := Control.new()
	add_child(holder)
	var nodes: Array[PerkNode] = []
	var defs: Array[PerkDef] = PerkTree.build(branches)
	for def in defs:
		var node: PerkNode = packed.instantiate()
		node.bind(def)
		node.level_label.text = "0/%d" % def.max_level
		holder.add_child(node)
		nodes.append(node)
	await get_tree().process_frame
	for i in defs.size():
		_rects.append(_label_rect(nodes[i], defs[i]))
		_ids.append(defs[i].id)
	holder.queue_free()

func test_no_two_perk_labels_overlap() -> void:
	await _build_all()
	for i in _rects.size():
		for j in range(i + 1, _rects.size()):
			assert_bool(_rects[i].intersects(_rects[j])).override_failure_message(
				"Labels of '%s' %s and '%s' %s overlap in the web." \
					% [_ids[i], _rects[i], _ids[j], _rects[j]]).is_false()

## A label reaching over a neighbouring node's circle reads as badly as one
## reaching over its label, and the fix for both is the same wrap width.
func test_no_perk_label_covers_another_node() -> void:
	await _build_all()
	var branches: PerkBranchList = load("res://data/prestige/all_branches.tres")
	var circles: Dictionary = {}
	for def in PerkTree.build(branches):
		circles[def.id] = Rect2(Vector2(def.world_x, def.world_y) \
			- Vector2(PerkWeb.NODE_SIZE, PerkWeb.NODE_SIZE) / 2.0,
			Vector2(PerkWeb.NODE_SIZE, PerkWeb.NODE_SIZE))
	for i in _rects.size():
		for id in circles:
			if id == _ids[i]:
				continue
			assert_bool(_rects[i].intersects(circles[id])).override_failure_message(
				"Label of '%s' %s covers node '%s' %s." \
					% [_ids[i], _rects[i], id, circles[id]]).is_false()
