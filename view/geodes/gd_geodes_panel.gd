extends PanelContainer
## VIEW: the Geodes tab of the Crystal Caves screen, the sink crystals drain
## into. A header stating what crystals are worth in geodes right now, and one
## card per boost.
##
## Lives under the Caves rather than as a tab of its own because crystals are
## what it is bought with, and that balance is already in the Caves header above
## these tabs - a second copy of it here would be the only thing a top-level tab
## added.
##
## There is no geode wallet and nothing to mint by hand: a boost is priced in
## geodes and buying one melts the crystals it is worth on the spot, so the
## header is a rate and a conversion, not a balance.

@export var lbl_available: Label
@export var lbl_conversion: Label
@export var vbox_boosts: VBoxContainer
@export var boost_card_scene: PackedScene

var _vm: GeodesViewModel

func _ready() -> void:
	bind(App.geodes_vm)
	_build_boosts()

func bind(vm: GeodesViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_header()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---
func _on_property_changed(property: StringName) -> void:
	match property:
		GeodesViewModel.PROP_GEODES_CHANGED:
			_refresh_header()

func _refresh_header() -> void:
	lbl_available.text = _vm.available_text
	lbl_conversion.text = _vm.conversion_text

func _build_boosts() -> void:
	for child in vbox_boosts.get_children():
		vbox_boosts.remove_child(child)
		child.queue_free()
	for vm in _vm.boost_vms_ordered():
		var card := boost_card_scene.instantiate()
		vbox_boosts.add_child(card)
		card.bind(vm)
