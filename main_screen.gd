@tool
extends Control

@export var vbox_nodes: VBoxContainer
@export var node_scene: PackedScene

func _ready() -> void:
	for child in vbox_nodes.get_children():
		vbox_nodes.remove_child(child)
		child.queue_free()
	
	var nodes = App.nodes.mycelium_nodes
	for index in range(nodes.size()):
		var node_scene = node_scene.instantiate()
		node_scene.node_level = index
		vbox_nodes.add_child(node_scene)
