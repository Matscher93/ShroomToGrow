extends PanelContainer
## VIEW: one mission as a thing that could be started - in the chooser sheet, and
## again in the ledger of expeditions still ahead.
##
## Both, from one scene. The ledger is this row with the picker and the button
## hidden and the status line showing instead; splitting it in two would have
## been the same name, reward and boon lines written twice.
##
## The picker opens on whoever is best placed for the mission rather than on
## whatever happens to be first in the roster, and every option is labelled with
## what that creature would actually make of the errand. Picking by name was the
## thing that made starting a mission a guess.

## The player chose to start this mission with the creature currently picked.
signal chosen(vm: MissionViewModel, creature_id: StringName)

@export var lbl_name: Label
@export var lbl_reward: Label
@export var lbl_boon: Label
@export var lbl_status: Label
@export var opt_creature: OptionButton
@export var btn_start: Button

var _vm: MissionViewModel
## False in the ledger, where the row is a thing to read rather than a thing to
## press.
var _actionable := true

func _ready() -> void:
	btn_start.pressed.connect(_on_start_pressed)
	opt_creature.item_selected.connect(_on_creature_selected)

func bind(vm: MissionViewModel, actionable: bool = true) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_actionable = actionable
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	_build_creatures()
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---

func _on_property_changed(property: StringName) -> void:
	if property != MissionViewModel.PROP_MISSION_CHANGED:
		return
	_build_creatures()
	refresh()

func refresh() -> void:
	var creature_id := _selected_creature()
	lbl_reward.text = _vm.reward_text(creature_id)
	lbl_boon.text = _vm.boon_text
	lbl_boon.visible = not lbl_boon.text.is_empty()
	lbl_status.text = _vm.status_text
	# In the chooser the picker already says who is going and how long it takes,
	# so the status line would only repeat it. In the ledger it is the whole row.
	lbl_status.visible = not _actionable
	opt_creature.visible = _actionable and opt_creature.item_count > 0
	btn_start.visible = _actionable
	if _actionable:
		btn_start.disabled = not _vm.can_start(creature_id)

# --- View -> VM ---

func _on_start_pressed() -> void:
	chosen.emit(_vm, _selected_creature())

func _on_creature_selected(_index: int) -> void:
	refresh()

# --- Building ---

## Rebuilds the picker, keeping the player's choice if that creature is still
## free and otherwise opening on the best-placed one. Without the first half,
## starting one mission would silently re-point every other row's picker; without
## the second, the row would open on whoever happens to be first in the roster,
## which is the guess this whole screen exists to remove.
func _build_creatures() -> void:
	var previous := _selected_creature()
	var best := _vm.best_creature_id
	opt_creature.clear()
	for creature in _vm.available_creatures():
		var label := creature.display_name
		if _vm.has_affinity(creature.id):
			label += " *"
		# What this creature would make of it, so the pick is by outcome rather
		# than by name.
		label += "  %s" % _vm.duration_text(creature.id)
		opt_creature.add_item(label)
		opt_creature.set_item_metadata(opt_creature.item_count - 1, creature.id)
		var wanted := previous if not previous.is_empty() else best
		if creature.id == wanted:
			opt_creature.select(opt_creature.item_count - 1)

func _selected_creature() -> StringName:
	if opt_creature.item_count <= 0:
		return &""
	var index := maxi(0, opt_creature.selected)
	var meta: Variant = opt_creature.get_item_metadata(index)
	return meta if meta is StringName else &""
