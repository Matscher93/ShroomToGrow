extends PanelContainer
## VIEW — prestige screen: biomass + sporate bar on top, the pannable perk
## web in the middle, a floating detail/buy panel on the bottom for
## whichever perk is currently selected.

@export var biomass_label: Label
@export var sporate_button: Button
@export var perk_web: PerkWeb
@export var detail_name: Label
@export var detail_effect: Label
@export var detail_cost: Label
@export var buy_button: Button

var _selected_id: StringName = &"core"

func _ready() -> void:
	sporate_button.pressed.connect(_on_sporate_pressed)
	buy_button.pressed.connect(_on_buy_pressed)
	perk_web.perk_selected.connect(_on_perk_selected)
	App.player_data.biomass_changed.connect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	_refresh_all()

func _exit_tree() -> void:
	if App.player_data.biomass_changed.is_connected(_on_changed):
		App.player_data.biomass_changed.disconnect(_on_changed)
	if App.prestige_upgrade_system.upgrades_changed.is_connected(_on_changed):
		App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)

func _on_changed(_arg = null) -> void:
	_refresh_all()

func _on_perk_selected(id: StringName) -> void:
	_selected_id = id
	_refresh_all()

func _on_sporate_pressed() -> void:
	App.prestige()

func _on_buy_pressed() -> void:
	App.buy_perk(_selected_id)

func _refresh_all() -> void:
	biomass_label.text = App.player_vm.biomass_text
	var pending := App.preview_biomass_gain()
	sporate_button.text = "Sporate (+%s biomass · resets colony, keeps perks)" % pending._to_string()
	sporate_button.disabled = not App.can_prestige()

	_refresh_detail()

func _refresh_detail() -> void:
	var def := App.perk_def(_selected_id)
	if def == null:
		return
	var lvl := App.prestige_upgrade_system.level(_selected_id)
	var status := App.perk_status(_selected_id)

	detail_name.text = "%s — Lv %d/%d" % [def.display_name, lvl, def.max_level]
	detail_effect.text = def.description if def.effects.is_empty() \
		else "+%.0f%% %s per level" % [def.effects[0].per_level * 100.0, def.effects[0].stat]

	if status == "locked":
		detail_cost.text = "Locked — unlock its parent first"
		buy_button.text = "Locked"
	elif lvl >= def.max_level:
		detail_cost.text = "Maxed"
		buy_button.text = "Maxed"
	else:
		detail_cost.text = "Cost: %s biomass" % App.prestige_upgrade_system.cost(_selected_id)._to_string()
		buy_button.text = "Buy"
	buy_button.disabled = not App.can_buy_perk(_selected_id)
