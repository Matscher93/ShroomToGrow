@tool
extends PanelContainer

@export var vbox_nodes: VBoxContainer
@export var node_scene: PackedScene

var _nodes: Array[MyceliumNode] = []

func _ready() -> void:
	for child in vbox_nodes.get_children():
		vbox_nodes.remove_child(child)
		child.queue_free()

	_nodes = App.nodes.mycelium_nodes
	for index in range(_nodes.size()):
		var node_scene_instance = node_scene.instantiate()
		node_scene_instance.node_level = index
		vbox_nodes.add_child(node_scene_instance)
		_nodes[index].manual_nodes_changed.connect(_update_visibility)
		_nodes[index].auto_nodes_changed.connect(_update_visibility)
	_update_visibility()

func _update_visibility(_value = null) -> void:
	for index in range(_nodes.size()):
		vbox_nodes.get_child(index).visible = _nodes[index].has_nodes() \
			or (index > 0 and _nodes[index - 1].has_nodes())
