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

var _vm: CrystalCavesViewModel

func _ready() -> void:
	bind(App.crystal_caves_vm)

func bind(vm: CrystalCavesViewModel) -> void:
	_vm = vm
	_build_boosts()

func _build_boosts() -> void:
	for child in vbox_boosts.get_children():
		vbox_boosts.remove_child(child)
		child.queue_free()
	for vm in _vm.boost_vms_ordered:
		var card := boost_card_scene.instantiate()
		vbox_boosts.add_child(card)
		card.bind(vm)
