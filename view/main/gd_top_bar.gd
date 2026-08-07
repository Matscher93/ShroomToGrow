extends PanelContainer
## VIEW: the row of overlay entry points above the currency pills. Right now the
## achievement archive is the only one, and its button carries the same
## notification dot a biome card uses for unspent points - the archive is off
## screen by default, so the dot is the only thing telling the player a tier is
## waiting.

signal achievements_pressed

@export var btn_achievements: Button
@export var image_achievements_notification: ColorRect

var _vm: AchievementsViewModel

func _ready() -> void:
	btn_achievements.pressed.connect(_on_achievements_pressed)
	if App.achievements_vm:
		bind(App.achievements_vm)

func bind(vm: AchievementsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(property: StringName) -> void:
	if property == AchievementsViewModel.PROP_HAS_CLAIMS:
		_refresh()

func _refresh() -> void:
	image_achievements_notification.visible = _vm.has_claims

func _on_achievements_pressed() -> void:
	achievements_pressed.emit()
