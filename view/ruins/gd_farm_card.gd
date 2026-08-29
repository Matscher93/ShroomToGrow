extends PanelContainer
## VIEW: one farm the player has opened, running or not.
##
## Every open farm has a row, and the stepper on it is the whole interface: from
## zero it starts the farm, and stepping the last worker off stops it again. There
## is no picking a farm to put in a plot, because there are no plots on screen -
## a farm nobody is on simply reads as a farm at zero workers.
##
## The bar is driven from _process rather than from a ViewModel notification: a
## cycle turns on the wall clock, so its progress is genuinely continuous and any
## polling interval shows up as the bar stepping. _process runs only while the
## farm is running and only while the card is on screen, so an idle farm and a
## hidden tab both cost nothing.

@export var lbl_name: Label
@export var lbl_countdown: Label
@export var lbl_reward: Label
@export var lbl_status: Label
@export var bar_progress: ProgressBar
@export var lbl_workers: Label
@export var btn_fewer: Button
@export var btn_more: Button

var _vm: FarmViewModel

## What the countdown label currently reads, so _process can skip the assignment
## on the fifty-nine frames a second where the string has not changed.
var _countdown_shown := ""

func _ready() -> void:
	set_process(false)
	btn_fewer.pressed.connect(_on_fewer_pressed)
	btn_more.pressed.connect(_on_more_pressed)

func bind(vm: FarmViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---

func _on_property_changed(property: StringName) -> void:
	match property:
		FarmViewModel.PROP_FARM_CHANGED:
			refresh()
		FarmViewModel.PROP_CLOCK_MOVED:
			# The board's poll. The bar does not need it - _process already has
			# the card covered - but a farm that ran on while this card sat on a
			# hidden tab has to catch up when it comes back.
			_refresh_countdown()

func refresh() -> void:
	# A rebuild can free this card while a press it started is still unwinding,
	# and _exit_tree() drops the ViewModel on the way out. Nothing to repaint.
	if _vm == null:
		return
	lbl_reward.text = _vm.reward_text
	lbl_workers.text = _vm.workers_text
	lbl_status.text = _vm.status_text
	lbl_status.visible = not lbl_status.text.is_empty()
	btn_fewer.disabled = not _vm.can_remove_worker
	btn_more.disabled = not _vm.can_add_worker
	# Dimmed while nobody is on it, so a glance down the list reads as what is
	# actually working.
	modulate = Color(1.0, 1.0, 1.0, 1.0 if _vm.is_running else 0.6)
	_refresh_countdown()

## The frame-by-frame half. Only the bar is written every frame; the label is
## written when what it says actually changes.
func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	bar_progress.value = _vm.progress_ratio
	var countdown := _vm.countdown_text
	if countdown == _countdown_shown:
		return
	_countdown_shown = countdown
	lbl_countdown.text = countdown

func _refresh_countdown() -> void:
	var countdown := _vm.countdown_text
	_countdown_shown = countdown
	lbl_countdown.text = countdown
	lbl_countdown.visible = not countdown.is_empty()
	bar_progress.visible = _vm.is_running
	bar_progress.value = _vm.progress_ratio
	# Nothing moves on a farm nobody is on, so it drops out of the frame loop.
	set_process(_vm.is_running)

# --- View -> VM ---

## Moving a worker re-snapshots the cycle, so the whole card is re-read rather
## than left to the frame loop - the duration under the bar just changed.
func _on_fewer_pressed() -> void:
	if _vm.remove_worker():
		refresh()

func _on_more_pressed() -> void:
	if _vm.add_worker():
		refresh()
