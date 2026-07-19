extends PanelContainer

@export var vbox_items: VBoxContainer
@export var item_to_spawn: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for child in vbox_items.get_children():
		vbox_items.remove_child(child)
		child.queue_free()
	
	var nodes = App.nodes.mycelium_nodes
	for index in range(nodes.size()):
		var node_scene_instance = item_to_spawn.instantiate()
		node_scene_instance.node_level = index
		vbox_items.add_child(node_scene_instance)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
