@tool
extends PanelContainer
## VIEW: the Crystal Caves screen. Three tabs: the crystal-bought automations,
## the geode sink crystals are melted down into, and the per-biome sequences
## the point-spending automation replays. The crystal balance stays in a shared
## header above them, since it is what they are all spent from.
##
## The Geodes tab is a self-contained scene with its own ViewModel (see
## view/geodes/), so it needs no wiring here beyond sitting in the TabContainer.
##
## Sequences sit last because they are set up once and then left alone, and the
## rows are long enough that they crowded the upgrade list they used to share.
##
## The achievement archive that mints those crystals used to lead here as a third
## tab. It moved to the top-bar overlay, which is reachable from every screen -
## claims pile up between visits, and having to walk to this screen to collect
## them was the only thing keeping it here.
##
## The Crystal Caves *biome* card (level, XP, points, size, its 10 upgrades)
## lives on the Biomes screen like every other biome. This screen is the hub the
## biome unlocks, not a second copy of that card.

@export var lbl_crystals: Label
@export var vbox_automations: VBoxContainer
@export var auto_unlock_section: VBoxContainer
@export var vbox_auto_unlocks: VBoxContainer
@export var vbox_sequences: VBoxContainer
@export var automation_card_scene: PackedScene
@export var biome_sequence_scene: PackedScene
@export var auto_unlock_row_scene: PackedScene

var _vm: CrystalCavesViewModel

func _ready() -> void:
	# Autoloads aren't instantiated for @tool scripts in the editor, so the
	# ViewModels only exist at runtime.
	if Engine.is_editor_hint():
		return

	bind(App.crystal_caves_vm)
	_build_automations()
	_build_auto_unlocks()
	_build_sequences()

func bind(vm: CrystalCavesViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_header()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(property: StringName) -> void:
	match property:
		CrystalCavesViewModel.PROP_CRYSTALS_TEXT:
			_refresh_header()

func _refresh_header() -> void:
	lbl_crystals.text = _vm.crystals_text

func _build_automations() -> void:
	_clear(vbox_automations)
	for vm in _vm.automation_vms_ordered:
		var card := automation_card_scene.instantiate()
		vbox_automations.add_child(card)
		card.bind(vm)

## One row per biome that can relock and has been reached at least once, under
## the automation cards: it is the same kind of purchase, and it is per-biome the
## way the cards are not. A biome shut by the last sporation keeps its row, since
## buying the row is how the player stops doing that unlock by hand.
## Built once for the same reason the sections are - the screen is respawned on
## every tab switch. The whole block hides while no biome offers one, so a fresh
## run does not carry a heading over an empty list.
func _build_auto_unlocks() -> void:
	_clear(vbox_auto_unlocks)
	var vms := _vm.auto_unlock_vms()
	auto_unlock_section.visible = not vms.is_empty()
	for vm in vms:
		var row := auto_unlock_row_scene.instantiate()
		vbox_auto_unlocks.add_child(row)
		row.bind(vm)

## One section per unlocked biome, each owning the sequence the point-spending
## automation replays for it. Built once: the screen is respawned on every tab
## switch, so a biome unlocked elsewhere shows up on the way back in.
func _build_sequences() -> void:
	_clear(vbox_sequences)
	for vm in _vm.sequence_vms():
		var section := biome_sequence_scene.instantiate()
		vbox_sequences.add_child(section)
		section.bind(vm)

func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
