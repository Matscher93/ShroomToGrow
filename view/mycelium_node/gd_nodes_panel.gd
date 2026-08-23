extends PanelContainer
## VIEW: the stack of node tier cards.
##
## A tier is shown once it holds anything, or once the tier below it does - so the
## next one to buy is always visible and the rest of the chain stays out of the way
## until it is reachable.

@export var vbox_nodes: VBoxContainer
@export var node_scene: PackedScene

## Holds structural refreshes back while the player has the pointer down, so a
## tick landing mid-press cannot free or reflow the button under their finger.
var _guard := PressGuard.new()
var _vms: Array[MyceliumNodeViewModel] = []

func _ready() -> void:
	add_child(_guard)
	for child in vbox_nodes.get_children():
		vbox_nodes.remove_child(child)
		child.queue_free()

	_vms.assign(App.mycelium_node_vms)
	for index in _vms.size():
		var node_scene_instance := node_scene.instantiate()
		node_scene_instance.node_level = index
		vbox_nodes.add_child(node_scene_instance)
		_vms[index].property_changed.connect(_on_property_changed)
	_update_visibility()

## App owns these ViewModels for the app's lifetime, so the panel disconnects but
## never disposes: the screen is rebuilt on every nav switch, and a disposed VM
## would take the rest of the app's bindings with it.
func _exit_tree() -> void:
	for vm in _vms:
		vm.property_changed.disconnect(_on_property_changed)
	_vms.clear()

func _on_property_changed(property: StringName) -> void:
	if property != MyceliumNodeViewModel.PROP_HAS_NODES: return
	_guard.run_when_free(&"visibility", _update_visibility)

func _update_visibility() -> void:
	for index in _vms.size():
		vbox_nodes.get_child(index).visible = _vms[index].has_nodes \
			or (index > 0 and _vms[index - 1].has_nodes)
