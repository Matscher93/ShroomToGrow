extends PanelContainer

@export var vbox_items: VBoxContainer
@export var item_to_spawn: PackedScene

var _nodes: Array[MyceliumNode] = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for child in vbox_items.get_children():
		vbox_items.remove_child(child)
		child.queue_free()

	_nodes = App.nodes.mycelium_nodes
	for index in range(_nodes.size()):
		var node_scene_instance = item_to_spawn.instantiate()
		node_scene_instance.node_level = index
		vbox_items.add_child(node_scene_instance)
		_nodes[index].manual_nodes_changed.connect(_update_visibility)
		_nodes[index].auto_nodes_changed.connect(_update_visibility)
	_update_visibility()

func _update_visibility(_value = null) -> void:
	for index in range(_nodes.size()):
		vbox_items.get_child(index).visible = _nodes[index].has_nodes() \
			or (index > 0 and _nodes[index - 1].has_nodes())
