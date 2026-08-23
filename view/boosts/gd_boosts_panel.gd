extends PanelContainer
## VIEW: the Boosts tab of the Crystal Caves screen, the sink crystals drain
## into. One card per boost, each priced in crystals.
##
## Lives under the Crystals screen rather than as a tab of its own because
## crystals are what it is bought with, and the top bar already shows that
## balance for this screen - a top-level tab would add nothing but a second
## place to look for the same number. That is also why there is no header here:
## the only number a header could carry is the one above it.
##
## Binds the screen's own CrystalCavesViewModel rather than one of its own: the
## card list is all this tab needs from the VM layer, and it is the same shape as
## the automations tab's list on the same screen. The cards carry their own
## per-boost VMs.

@export var vbox_boosts: VBoxContainer
@export var boost_card_scene: PackedScene

func _ready() -> void:
	build(App.crystal_caves_vm)

## Takes the list and keeps nothing. The ordered card list is fixed for the app's
## lifetime and each card binds its own per-boost VM, so there is no live state
## here to subscribe to - and holding a reference to an App-owned VM that this
## never listens to or releases only looks like a binding.
func build(vm: CrystalCavesViewModel) -> void:
	for child in vbox_boosts.get_children():
		vbox_boosts.remove_child(child)
		child.queue_free()
	for boost_vm in vm.boost_vms_ordered:
		var card := boost_card_scene.instantiate()
		vbox_boosts.add_child(card)
		card.bind(boost_vm)
