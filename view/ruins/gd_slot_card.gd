extends PanelContainer
## VIEW: one place on one of the two boards - filled with an expedition or a
## farm, or empty and waiting to be filled.
##
## Serves both kinds from one scene. MissionSlotViewModel already answers every
## question that differs between them - what the row is called, what the button
## says, whether the bar wraps - so a second scene would be the same nodes with
## different strings baked in.
##
## An empty slot emits `fill_requested` rather than doing anything itself. Picking
## a mission is a choice made in the chooser sheet, and the panel owns opening it.
##
## The bar is driven from _process rather than from a ViewModel notification, for
## the reason MissionCard's was: a mission finishes on the wall clock, so its
## progress is genuinely continuous and any polling interval shows up as the bar
## stepping. _process runs only while this slot holds something and only while the
## card is on screen, so an empty board and a hidden tab both cost nothing.

## The player tapped an empty slot. Carries which board and which place, so the
## panel can open the chooser against the right one.
signal fill_requested(is_farm: bool)

@export var lbl_name: Label
@export var lbl_creature: Label
@export var lbl_countdown: Label
@export var lbl_reward: Label
@export var lbl_boon: Label
@export var bar_progress: ProgressBar
@export var btn_action: Button

var _vm: MissionSlotViewModel

## What the countdown label currently reads, so _process can skip the assignment
## on the fifty-nine frames a second where the string has not changed.
var _countdown_shown := ""
## Whether the errand had already landed last frame, so the buttons are only
## re-read on the frame that changes.
var _was_complete := false

func _ready() -> void:
	set_process(false)
	btn_action.pressed.connect(_on_action_pressed)

func bind(vm: MissionSlotViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---

func _on_property_changed(property: StringName) -> void:
	match property:
		MissionSlotViewModel.PROP_SLOT_CHANGED:
			refresh()
		MissionSlotViewModel.PROP_CLOCK_MOVED:
			# The board's poll. The bar does not need it - _process already has
			# the card covered - but a slot that filled or landed while this card
			# was on a hidden tab has to catch up when it comes back.
			_refresh_countdown()

func refresh() -> void:
	var filled := _vm.is_filled
	lbl_name.text = _vm.mission_name
	lbl_creature.text = _vm.creature_name
	lbl_creature.visible = not lbl_creature.text.is_empty()
	lbl_reward.text = _vm.reward_text
	lbl_reward.visible = not lbl_reward.text.is_empty()
	lbl_boon.text = _vm.boon_text
	lbl_boon.visible = not lbl_boon.text.is_empty()
	btn_action.text = _vm.action_text
	# An empty slot's button is the way in to the chooser, so it is always live.
	btn_action.disabled = filled and not _vm.can_act
	# Dimmed while empty, so a glance down the board reads as what is working.
	modulate = Color(1.0, 1.0, 1.0, 1.0 if filled else 0.6)
	_refresh_countdown()

## The frame-by-frame half. Only the bar is written every frame; the label and
## the button are written when what they say actually changes.
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
	bar_progress.visible = _vm.is_filled
	bar_progress.value = _vm.progress_ratio
	# Nothing moves in an empty slot, so it drops out of the frame loop entirely.
	set_process(_vm.is_filled)

# --- View -> VM ---

func _on_action_pressed() -> void:
	if _vm.is_filled:
		_vm.act()
		return
	fill_requested.emit(_vm.is_farm)
