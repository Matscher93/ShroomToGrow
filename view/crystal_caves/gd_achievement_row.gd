extends PanelContainer
## VIEW: one row of the Crystal Caves achievement archive. Bound to a persistent
## AchievementViewModel owned by App; this only renders it.

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_tier: Label
@export var lbl_progress: Label
@export var lbl_reward: Label
@export var bar_progress: ProgressBar
@export var btn_claim: Button

var _vm: AchievementViewModel

func _ready() -> void:
	btn_claim.pressed.connect(_on_claim_pressed)

func bind(vm: AchievementViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_description.text = _vm.description
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(_property: StringName) -> void:
	refresh()

func refresh() -> void:
	lbl_tier.text = _vm.tier_text
	lbl_progress.text = _vm.progress_text
	lbl_reward.text = _vm.reward_text
	bar_progress.value = _vm.progress_ratio * 100.0
	# Kept visible but disabled rather than hidden, so a row doesn't change
	# height the moment a tier completes.
	btn_claim.text = _vm.claim_text
	btn_claim.disabled = not _vm.can_claim

func _on_claim_pressed() -> void:
	_vm.claim()
