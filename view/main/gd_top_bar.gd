extends PanelContainer
## VIEW: the row of overlay entry points above the currency pills. Two of them:
## the player level chip and the achievement archive.
##
## Both carry the same notification dot a biome card uses for unspent points.
## Both overlays are off screen by default, so the dot is the only thing telling
## the player something is waiting - a claimable tier, an unspent Level Point, or
## today's daily reward.

signal achievements_pressed
signal growth_pressed

@export var btn_achievements: Button
@export var image_achievements_notification: ColorRect
@export var btn_growth: Button
@export var lbl_growth_level: Label
@export var image_growth_notification: ColorRect

var _vm: AchievementsViewModel
var _growth_vm: GrowthViewModel

func _ready() -> void:
	btn_achievements.pressed.connect(_on_achievements_pressed)
	btn_growth.pressed.connect(_on_growth_pressed)
	if App.achievements_vm:
		bind(App.achievements_vm)
	if App.growth_vm:
		bind_growth(App.growth_vm)

func bind(vm: AchievementsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh()

func bind_growth(vm: GrowthViewModel) -> void:
	if _growth_vm:
		_growth_vm.property_changed.disconnect(_on_growth_property_changed)
	_growth_vm = vm
	_growth_vm.property_changed.connect(_on_growth_property_changed)
	_refresh_growth()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null
	if _growth_vm:
		_growth_vm.property_changed.disconnect(_on_growth_property_changed)
		_growth_vm = null

func _on_property_changed(property: StringName) -> void:
	if property == AchievementsViewModel.PROP_HAS_CLAIMS:
		_refresh()

## Every notification repaints the chip: the level number and the dot come from
## different sources - lifetime nutrients for one, unspent points and the day's
## claim for the other - and there is no property that moves only one of them.
func _on_growth_property_changed(_property: StringName) -> void:
	_refresh_growth()

func _refresh() -> void:
	image_achievements_notification.visible = _vm.has_claims

func _refresh_growth() -> void:
	lbl_growth_level.text = "Lv %s" % _growth_vm.level_number
	image_growth_notification.visible = _growth_vm.has_alert

func _on_achievements_pressed() -> void:
	achievements_pressed.emit()

func _on_growth_pressed() -> void:
	growth_pressed.emit()
