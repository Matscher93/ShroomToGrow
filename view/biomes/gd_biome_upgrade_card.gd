@tool
class_name BiomeUpgradeCard
extends PanelContainer
## VIEW — the detail panel for whichever biome upgrade is currently selected
## in the 5x2 grid (BiomePanel/gd_biome_panel.gd). Embedded once, statically,
## per biome card; BiomePanel calls select_upgrade() whenever a grid slot is
## picked to rebind it. Binds straight to App.biome_upgrade_system for the
## given upgrade_id (no per-upgrade VM), same way MyceliumNodePanel binds
## straight to App.upgrade_system.

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

func _ready() -> void:
	_update_shader()
	upgrade_buy_button.pressed.connect(_on_buy_pressed)
	App.biome_upgrade_system.upgrades_changed.connect(refresh)
	lbl_upgrade_cost.text = "1 pt"
	if upgrade_id != &"":
		select_upgrade(upgrade_id, biome_key)

func _exit_tree() -> void:
	if App.biome_upgrade_system.upgrades_changed.is_connected(refresh):
		App.biome_upgrade_system.upgrades_changed.disconnect(refresh)

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
	var def := App.biome_upgrade_system.def(upgrade_id)
	lbl_upgrade_name.text = def.display_name if def else ""
	refresh()

func refresh() -> void:
	var def := App.biome_upgrade_system.def(upgrade_id)
	var unlocked := App.is_biome_upgrade_unlocked(upgrade_id, biome_key)
	if unlocked:
		lbl_upgrade_desc.text = def.description if def else ""
	else:
		var needed := def.min_biome_points_spent if def else 0
		lbl_upgrade_desc.text = "Locked — requires %d points spent in this biome." % needed
	var lvl := App.biome_upgrade_system.level(upgrade_id)
	lbl_upgrade_level.text = "Lv %d" % lvl
	var amount := App.biome_upgrade_system.effect_amount(upgrade_id, App.resolve_context)
	lbl_upgrade_effect.text = "now +%s%%" % [amount.scale(100.0)._to_string()]
	var can_buy := App.can_buy_biome_upgrade(upgrade_id, biome_key)
	upgrade_buy_button.disabled = not can_buy
	panel_buy_upgrade.set_enabled(can_buy)

func _on_buy_pressed() -> void:
	App.buy_biome_upgrade(upgrade_id, biome_key)
