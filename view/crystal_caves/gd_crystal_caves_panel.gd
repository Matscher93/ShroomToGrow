@tool
extends PanelContainer
## VIEW: the Crystal Caves screen. Two tabs: the achievement archive, and the
## crystal-bought upgrades it pays for. The crystal balance stays in a shared
## header above them, since it is what both tabs are about.
##
## Achievements lead because that is the tab with something to do on it: claims
## pile up between visits, upgrades only change when the player buys one.
##
## The Crystal Caves *biome* card (level, XP, points, size, its 10 upgrades)
## lives on the Biomes screen like every other biome. This screen is the hub the
## biome unlocks, not a second copy of that card.

## Tab order, matching the child order of the TabContainer in the scene.
const TAB_ACHIEVEMENTS := 0
const TAB_UPGRADES := 1

@export var lbl_crystals: Label
@export var lbl_tiers: Label
@export var btn_claim_all: Button
@export var tab_container: TabContainer
@export var vbox_automations: VBoxContainer
@export var vbox_sequences: VBoxContainer
@export var vbox_achievements: VBoxContainer
@export var automation_card_scene: PackedScene
@export var achievement_row_scene: PackedScene
@export var biome_sequence_scene: PackedScene

var _vm: CrystalCavesViewModel

func _ready() -> void:
	# Autoloads aren't instantiated for @tool scripts in the editor, so the
	# ViewModels only exist at runtime.
	if Engine.is_editor_hint():
		return

	btn_claim_all.pressed.connect(_on_claim_all_pressed)
	bind(App.crystal_caves_vm)
	_build_automations()
	_build_sequences()
	_build_achievements()

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
		CrystalCavesViewModel.PROP_CRYSTALS_TEXT, CrystalCavesViewModel.PROP_TIERS_TEXT, \
		CrystalCavesViewModel.PROP_CLAIM_ALL:
			_refresh_header()

func _refresh_header() -> void:
	lbl_crystals.text = _vm.crystals_text
	lbl_tiers.text = _vm.tiers_text
	btn_claim_all.text = _vm.claim_all_text
	btn_claim_all.disabled = not _vm.has_claims
	# The whole reason to switch tabs, so it has to be visible from the other one.
	tab_container.set_tab_title(TAB_ACHIEVEMENTS, _vm.achievements_tab_text)

func _on_claim_all_pressed() -> void:
	_vm.claim_all()

func _build_automations() -> void:
	_clear(vbox_automations)
	for vm in _vm.automation_vms_ordered:
		var card := automation_card_scene.instantiate()
		vbox_automations.add_child(card)
		card.bind(vm)

## One section per unlocked biome, each owning the sequence the point-spending
## automation replays for it. Built once: the screen is respawned on every tab
## switch, so a biome unlocked elsewhere shows up on the way back in.
func _build_sequences() -> void:
	_clear(vbox_sequences)
	for vm in _vm.sequence_vms():
		var section := biome_sequence_scene.instantiate()
		vbox_sequences.add_child(section)
		section.bind(vm)

func _build_achievements() -> void:
	_clear(vbox_achievements)
	for vm in _vm.achievement_vms_ordered:
		var row := achievement_row_scene.instantiate()
		vbox_achievements.add_child(row)
		row.bind(vm)

func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
