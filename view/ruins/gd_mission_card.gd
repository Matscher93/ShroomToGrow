extends PanelContainer
## VIEW: one mission on the board. Picks a creature, sends it, counts it down and
## collects it.
##
## The creature picker is rebuilt whenever the roster moves rather than bound
## once: which creatures are free changes every time one is sent out or comes
## home, and a picker offering a busy creature is a button that refuses itself.
##
## The bar is driven from _process rather than from a ViewModel notification.
## A mission finishes on the wall clock, so its progress is genuinely continuous
## and there is no signal to bind: any polling interval shows up as the bar
## jumping in steps that size. The label beside it is not driven that way, since
## it only ever renders whole seconds - see _process().
##
## _process runs only while a creature is actually out, and only while the card
## is on screen, so an idle board and a hidden tab both cost nothing.

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_status: Label
@export var lbl_reward: Label
@export var lbl_countdown: Label
@export var bar_progress: ProgressBar
@export var opt_creature: OptionButton
@export var btn_action: Button

var _vm: MissionViewModel

## What the countdown label currently reads, so _process can skip the assignment
## on the fifty-nine frames a second where the string has not changed.
var _countdown_shown := ""
## Whether the errand had already landed last frame, so the buttons are only
## re-read on the frame that changes.
var _was_complete := false

func _ready() -> void:
	set_process(false)
	btn_action.pressed.connect(_on_action_pressed)
	opt_creature.item_selected.connect(_on_creature_selected)

func bind(vm: MissionViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_description.text = _vm.description
	_build_creatures()
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---

func _on_property_changed(property: StringName) -> void:
	match property:
		MissionViewModel.PROP_MISSION_CHANGED:
			_build_creatures()
			refresh()
		MissionViewModel.PROP_CLOCK_MOVED:
			# The board's poll. The bar does not need it - _process already has
			# the card covered - but a mission that finished while this card was
			# on a hidden tab has to catch up when it comes back.
			_refresh_countdown()

func refresh() -> void:
	lbl_status.text = _vm.status_text
	lbl_reward.text = _vm.reward_text(_selected_creature())
	# The picker is only useful while the mission is idle and reachable. Out on an
	# errand it would offer to change a decision already taken.
	opt_creature.visible = _vm.is_unlocked and not _vm.is_active \
		and opt_creature.item_count > 0
	if _vm.is_active:
		btn_action.text = "Collect"
		btn_action.disabled = not _vm.is_complete
	else:
		btn_action.text = "Send"
		btn_action.disabled = not _vm.can_send(_selected_creature())
	_refresh_countdown()

## The frame-by-frame half. Only the bar is written every frame; the label and
## the buttons are written when what they say actually changes.
func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	bar_progress.value = _vm.progress_ratio

	var complete := _vm.is_complete
	if complete != _was_complete:
		_was_complete = complete
		# The frame the errand lands is the frame Collect has to come alive.
		refresh()
		return

	var countdown := _vm.countdown_text
	if countdown == _countdown_shown:
		return
	_countdown_shown = countdown
	lbl_countdown.text = countdown

func _refresh_countdown() -> void:
	var countdown := _vm.countdown_text
	_countdown_shown = countdown
	_was_complete = _vm.is_complete
	lbl_countdown.text = countdown
	lbl_countdown.visible = not countdown.is_empty()
	bar_progress.visible = _vm.is_active
	bar_progress.value = _vm.progress_ratio
	# Idle, the second line says what a send would take rather than nothing: it is
	# what the creature picker is being chosen against.
	if not _vm.is_active and _vm.is_unlocked and opt_creature.item_count > 0:
		lbl_countdown.text = _vm.duration_text(_selected_creature())
		_countdown_shown = lbl_countdown.text
		lbl_countdown.visible = true
	# Nothing moves on an idle card, so it drops out of the frame loop entirely.
	set_process(_vm.is_active)

# --- View -> VM ---

func _on_action_pressed() -> void:
	if _vm.is_active:
		_vm.collect()
		return
	_vm.send(_selected_creature())

func _on_creature_selected(_index: int) -> void:
	refresh()

# --- Building ---

## Rebuilds the picker, keeping the player's choice if that creature is still
## free. Without that, sending one mission would silently re-point every other
## card's picker at whatever ended up first in the list.
func _build_creatures() -> void:
	var previous := _selected_creature()
	opt_creature.clear()
	for creature in _vm.available_creatures():
		var label := creature.display_name
		if _vm.has_affinity(creature.id):
			label += "  *"
		opt_creature.add_item(label)
		opt_creature.set_item_metadata(opt_creature.item_count - 1, creature.id)
		if creature.id == previous:
			opt_creature.select(opt_creature.item_count - 1)

func _selected_creature() -> StringName:
	if opt_creature.item_count <= 0:
		return &""
	var index := maxi(0, opt_creature.selected)
	var meta: Variant = opt_creature.get_item_metadata(index)
	return meta if meta is StringName else &""
