@tool
class_name BiomeUpgradeCard
extends PanelContainer
## VIEW — one biome upgrade card, spawned N times per biome (10/biome) by
## BiomePanel (gd_biome_panel.gd) into vbox_upgrade_cards. Binds straight to
## App.biome_upgrade_system for the given upgrade_id (no per-card VM), same
## way MyceliumNodePanel binds straight to App.upgrade_system.

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
	var def := App.biome_upgrade_system.def(upgrade_id)
	lbl_upgrade_name.text = def.display_name if def else ""
	lbl_upgrade_desc.text = def.description if def else ""
	refresh()

func _exit_tree() -> void:
	if App.biome_upgrade_system.upgrades_changed.is_connected(refresh):
		App.biome_upgrade_system.upgrades_changed.disconnect(refresh)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader() -> void:
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func refresh() -> void:
	var lvl := App.biome_upgrade_system.level(upgrade_id)
	lbl_upgrade_level.text = "Lv %d" % lvl
	var amount := App.biome_upgrade_system.effect_amount(upgrade_id, App.resolve_context)
	lbl_upgrade_effect.text = "now +%s%%" % [amount.scale(100.0)._to_string()]
	var can_buy := App.can_buy_biome_upgrade(upgrade_id, biome_key)
	upgrade_buy_button.disabled = not can_buy
	panel_buy_upgrade.set_enabled(can_buy)

func _on_buy_pressed() -> void:
	App.buy_biome_upgrade(upgrade_id, biome_key)
