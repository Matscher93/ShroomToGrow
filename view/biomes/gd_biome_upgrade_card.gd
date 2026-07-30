@tool
class_name BiomeUpgradeCard
extends PanelContainer
## VIEW — the detail panel for whichever biome upgrade is currently selected
## in the 5x2 grid (BiomePanel/gd_biome_panel.gd). Embedded once, statically,
## per biome card; BiomePanel calls select_upgrade() whenever a grid slot is
## picked, which rebinds a fresh BiomeUpgradeViewModel for that upgrade_id
## (disposing the previous one) — mirrors how PrestigePanel rebinds a
## PerkViewModel per selection.

@export var color_param: String
@export var upgrade_id: StringName
@export var biome_key: StringName

@export var lbl_upgrade_name: Label
@export var lbl_upgrade_desc: Label
@export var lbl_upgrade_level: Label
@export var lbl_upgrade_effect: Label
@export var panel_buy_upgrade: PanelContainer
@export var lbl_upgrade_cost: Label
@export var upgrade_buy_button: Button

var _vm: BiomeUpgradeViewModel

func _ready() -> void:
	_update_shader()
	lbl_upgrade_cost.text = "1 pt"

	# select_upgrade() builds a ViewModel that reads the App autoload, which
	# isn't instantiated for @tool scripts running in the editor.
	if Engine.is_editor_hint():
		return

	upgrade_buy_button.pressed.connect(_on_buy_pressed)
	if upgrade_id != &"":
		select_upgrade(upgrade_id, biome_key)

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm.dispose()
		_vm = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func _set_color(in_color: Color) -> void:
	if material:
		material.set_shader_parameter(color_param, in_color)
	panel_buy_upgrade._set_color(in_color)

func select_upgrade(id: StringName, key: StringName) -> void:
	upgrade_id = id
	biome_key = key
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm.dispose()
	_vm = BiomeUpgradeViewModel.new(id, key)
	_vm.property_changed.connect(_on_property_changed)
	refresh()

func _on_property_changed(_property: StringName) -> void:
	refresh()

func refresh() -> void:
	lbl_upgrade_name.text = _vm.name_text
	lbl_upgrade_desc.text = _vm.desc_text
	lbl_upgrade_level.text = _vm.level_text
	lbl_upgrade_effect.text = _vm.effect_text
	upgrade_buy_button.disabled = not _vm.can_buy
	panel_buy_upgrade.set_enabled(_vm.can_buy)

func _on_buy_pressed() -> void:
	_vm.buy()
