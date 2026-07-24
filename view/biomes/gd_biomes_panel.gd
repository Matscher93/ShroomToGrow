extends PanelContainer
## VIEW — the biome hub: one row per BiomeDef, showing lock/unlock, level
## progress, and the biome's single point-bought upgrade. Built entirely in
## code (plain Controls, no custom theme) — functional scaffold, not final art.

@export var vbox_items: VBoxContainer

var _controls: Dictionary = {}  # StringName -> Dictionary of row Controls

func _ready() -> void:
	for child in vbox_items.get_children():
		vbox_items.remove_child(child)
		child.queue_free()
	_controls.clear()

	for def in App.biomes.biomes:
		_build_row(def)

	App.biomes_data.biome_unlocked.connect(_on_changed)
	App.biome_upgrade_system.upgrades_changed.connect(_on_changed)
	App.player_data.nutrients_changed.connect(_on_changed)
	App.player_data.water_changed.connect(_on_changed)
	App.player_data.biomass_changed.connect(_on_changed)
	_refresh_all()

func _exit_tree() -> void:
	if App.biomes_data.biome_unlocked.is_connected(_on_changed):
		App.biomes_data.biome_unlocked.disconnect(_on_changed)
	if App.biome_upgrade_system.upgrades_changed.is_connected(_on_changed):
		App.biome_upgrade_system.upgrades_changed.disconnect(_on_changed)
	if App.player_data.nutrients_changed.is_connected(_on_changed):
		App.player_data.nutrients_changed.disconnect(_on_changed)
	if App.player_data.water_changed.is_connected(_on_changed):
		App.player_data.water_changed.disconnect(_on_changed)
	if App.player_data.biomass_changed.is_connected(_on_changed):
		App.player_data.biomass_changed.disconnect(_on_changed)

func _on_changed(_arg = null) -> void:
	_refresh_all()

# --- row construction ---

func _build_row(def: BiomeDef) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_constant_override("margin_left", 8)

	var box := VBoxContainer.new()
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)

	var name_label := Label.new()
	name_label.text = def.display_name
	header.add_child(name_label)

	var status_label := Label.new()
	header.add_child(status_label)

	var unlock_button := Button.new()
	unlock_button.text = "Unlock"
	unlock_button.pressed.connect(func() -> void: App.unlock_biome(def.key))
	box.add_child(unlock_button)

	var xp_label := Label.new()
	box.add_child(xp_label)

	var points_label := Label.new()
	box.add_child(points_label)

	var upgrade_row := HBoxContainer.new()
	box.add_child(upgrade_row)

	var upgrade_label := Label.new()
	upgrade_row.add_child(upgrade_label)

	var upgrade_button := Button.new()
	upgrade_button.text = "Spend point"
	var upgrade_id := _upgrade_id_for(def.key)
	upgrade_button.pressed.connect(func() -> void: App.buy_biome_upgrade(upgrade_id, def.key))
	upgrade_row.add_child(upgrade_button)

	vbox_items.add_child(panel)

	_controls[def.key] = {
		"status": status_label,
		"unlock_button": unlock_button,
		"xp": xp_label,
		"points": points_label,
		"upgrade_label": upgrade_label,
		"upgrade_button": upgrade_button,
	}

## Each biome currently ships exactly one upgrade, bought with that biome's
## own level points. Add more by extending this map alongside new .tres defs
## under data/upgrades/biomes/<key>/.
func _upgrade_id_for(key: StringName) -> StringName:
	match key:
		&"forest": return &"DenseMycelium"
		&"symbiosis": return &"SymbioticBloom"
		&"permafrost": return &"FrozenSpores"
		_: return &""

func _upgrade_name_for(key: StringName) -> String:
	match key:
		&"forest": return "Dense Mycelium"
		&"symbiosis": return "Symbiotic Bloom"
		&"permafrost": return "Frozen Spores"
		_: return ""

# --- refresh ---

func _refresh_all() -> void:
	for def in App.biomes.biomes:
		_refresh_row(def)

func _refresh_row(def: BiomeDef) -> void:
	var c: Dictionary = _controls[def.key]
	var unlocked := App.biomes_data.is_unlocked(def.key)

	c["unlock_button"].visible = not unlocked
	c["unlock_button"].disabled = not App.can_unlock_biome(def.key)
	c["status"].text = "Unlocked" if unlocked \
		else "Locked — costs %s" % def.unlock_cost._to_string()

	c["xp"].visible = unlocked
	c["points"].visible = unlocked
	c["upgrade_label"].visible = unlocked
	c["upgrade_button"].visible = unlocked
	if not unlocked:
		return

	var lvl_info := App.biome_level(def.key)
	c["xp"].text = "Lv %d — %d/%d %s" % [lvl_info.level, lvl_info.into, lvl_info.need, def.xp_label]

	var points := App.biome_available_points(def.key)
	c["points"].text = "%d point(s) available" % points

	var upgrade_id := _upgrade_id_for(def.key)
	var upgrade_lvl := App.biome_upgrade_system.level(upgrade_id)
	c["upgrade_label"].text = "%s — Lv %d" % [_upgrade_name_for(def.key), upgrade_lvl]
	c["upgrade_button"].disabled = points < 1
