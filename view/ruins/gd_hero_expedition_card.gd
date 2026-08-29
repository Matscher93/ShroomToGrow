extends PanelContainer
## VIEW: one hero's row on the expedition board - where it stands in its chain,
## what step is in front of it, and the one button that moves it.
##
## One row per hero rather than one per place, and no chooser behind it: a hero
## walks exactly one chain in order, so the step it could run next is not a choice
## and never was. What used to be a sheet of options is now the row itself.
##
## The bar is driven from _process for the reason every countdown here is: an
## expedition finishes on the wall clock, so its progress is continuous and any
## polling interval shows up as the bar stepping. It runs only while the hero is
## out and only while the card is on screen.

@export var lbl_name: Label
@export var lbl_level: Label
@export var lbl_chain: Label
@export var lbl_step: Label
@export var lbl_countdown: Label
@export var lbl_reward: Label
@export var lbl_boon: Label
@export var lbl_status: Label
@export var bar_progress: ProgressBar
@export var btn_action: Button

var _vm: HeroExpeditionViewModel

## What the countdown label currently reads, so _process can skip the assignment
## on the fifty-nine frames a second where the string has not changed.
var _countdown_shown := ""
## Whether the step had already landed last frame, so the button is only re-read
## on the frame that changes.
var _was_complete := false

func _ready() -> void:
	set_process(false)
	btn_action.pressed.connect(_on_action_pressed)

func bind(vm: HeroExpeditionViewModel) -> void:
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
		HeroExpeditionViewModel.PROP_EXPEDITION_CHANGED:
			refresh()
		HeroExpeditionViewModel.PROP_CLOCK_MOVED:
			# The board's poll, for a card that was on a hidden tab while its
			# expedition landed. A card on screen drives its own bar.
			_refresh_countdown()

func refresh() -> void:
	# A rebuild can free this card while a press it started is still unwinding,
	# and _exit_tree() drops the ViewModel on the way out. Nothing to repaint.
	if _vm == null:
		return
	lbl_level.text = _vm.level_text
	lbl_chain.text = _vm.chain_text
	lbl_step.text = _vm.step_name
	lbl_reward.text = _vm.step_reward_text
	lbl_reward.visible = not lbl_reward.text.is_empty()
	lbl_boon.text = _vm.step_boon_text
	lbl_boon.visible = not lbl_boon.text.is_empty()
	lbl_status.text = _vm.status_text
	lbl_status.visible = not lbl_status.text.is_empty()
	btn_action.text = _vm.action_text
	btn_action.disabled = not _vm.can_act
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
		# The frame the expedition lands is the frame Collect has to come alive.
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
	bar_progress.visible = _vm.is_out
	bar_progress.value = _vm.progress_ratio
	# Nothing moves while the hero is home, so the card drops out of the frame
	# loop entirely.
	set_process(_vm.is_out)

# --- View -> VM ---

func _on_action_pressed() -> void:
	if _vm.act():
		refresh()
