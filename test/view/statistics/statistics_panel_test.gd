extends GdUnitTestSuite
## Every tab of the statistics overlay builds against the live App.
##
## The smoke test only ever sees the tab the sheet opens on, and three of the
## four are built by code that never runs until a button is pressed - including
## the bonus breakdown, which is the one walking every upgrade track. A tab that
## crashes on open would otherwise ship.
##
## Pressed through the buttons rather than by calling the build methods, so the
## PressGuard deferral between a press and the rebuild is exercised too.

const PANEL_SCENE := preload("res://view/statistics/sc_statistics_panel.tscn")

var _panel: Control

func before_test() -> void:
	_panel = PANEL_SCENE.instantiate()
	add_child(_panel)
	await get_tree().process_frame

func after_test() -> void:
	remove_child(_panel)
	_panel.free()

## Presses go through the guard, which defers the rebuild by a frame.
func _open(button: Button) -> void:
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

## The panel's script is anonymous, so every read off it comes back as a Variant -
## these two give the members their types back rather than spelling one out at
## each of the dozen call sites.
func _content() -> VBoxContainer:
	return _panel.vbox_content

func _empty() -> Label:
	return _panel.lbl_empty

func test_records_is_never_empty() -> void:
	# The records tab reads live PlayerData, so it always has rows even on a save
	# that has recorded nothing - which is what makes it the tab to open on.
	assert_int(_content().get_child_count()).is_greater(0)
	assert_bool(_empty().visible).is_false()

func test_every_tab_opens() -> void:
	for button: Button in [_panel.btn_timeline, _panel.btn_runs, _panel.btn_bonuses,
			_panel.btn_records]:
		await _open(button)
		# Either rows or the explanation of why there are none, never both and
		# never neither.
		var has_rows := _content().get_child_count() > 0
		assert_bool(has_rows != _empty().visible).is_true()

func test_the_runs_tab_always_carries_the_run_in_progress() -> void:
	await _open(_panel.btn_runs)
	assert_int(_content().get_child_count()).is_greater(0)
	assert_bool(_empty().visible).is_false()

func test_the_bonuses_tab_lists_a_levelled_upgrade() -> void:
	var track := App.upgrade_system
	var levelled: StringName = &""
	for id: StringName in App.nodes.mycelium_nodes.map(func(n: MyceliumNode) -> StringName:
			return n.id_key):
		if track.has_def(id):
			levelled = id
			break
	if levelled.is_empty():
		# Symbiosis ids are authored, so an empty track means the data moved
		# under this test rather than that the tab is broken.
		return
	var before := track.level(levelled)
	track.set_level_for_analysis(levelled, before + 1)
	await _open(_panel.btn_bonuses)
	track.set_level_for_analysis(levelled, before)

	assert_int(_content().get_child_count()).is_greater(0)
	assert_bool(_empty().visible).is_false()

## Levels one perk so the bonus tab has something to group, and hands back the
## undo. Perks rather than symbiosis upgrades: App.perk_defs is keyed by the same
## id prestige_upgrade_system registers, so a perk id is always a real def -
## where a node's id_key is a guess that data can move out from under.
func _with_a_levelled_perk() -> Callable:
	var track := App.prestige_upgrade_system
	var id: StringName = App.perk_defs.keys()[0]
	var before := track.level(id)
	track.set_level_for_analysis(id, maxi(before, 1))
	return func() -> void: track.set_level_for_analysis(id, before)

func test_bonus_resources_start_collapsed() -> void:
	var restore := _with_a_levelled_perk()
	await _open(_panel.btn_bonuses)
	assert_int(_content().get_child_count()).is_greater(0)
	for card in _content().get_children():
		# Closed, and nothing built under it - a card that only hid its rows
		# would still have walked every track to make them.
		assert_bool(card.rows.visible).is_false()
		assert_int(card.rows.get_child_count()).is_equal(0)
	restore.call()

func test_pressing_a_bonus_card_folds_it_open_and_shut() -> void:
	var restore := _with_a_levelled_perk()
	await _open(_panel.btn_bonuses)

	# Each press rebuilds the whole tab, so the card has to be read again after
	# every one of them - the node pressed is freed by the rebuild it triggers.
	_content().get_child(0).btn_header.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var opened: Node = _content().get_child(0)
	assert_bool(opened.rows.visible).is_true()
	assert_int(opened.rows.get_child_count()).is_greater(0)

	opened.btn_header.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_content().get_child(0).rows.visible).is_false()
	restore.call()

## Guards the mapping rather than the icons: a records row added later without a
## key would draw the blank the effect lines use, and nothing else would notice.
func test_every_records_row_draws_an_icon() -> void:
	assert_int(_content().get_child_count()).is_greater(0)
	for row in _content().get_children():
		var shader_material := row.icon.material as ShaderMaterial
		var color: Color = shader_material.get_shader_parameter(&"icon_color")
		assert_float(color.a).is_equal(1.0)

## The tint is joined to the biome through the *display name* a finished run
## recorded - no key was ever stored - so this covers the one join in the overlay
## a rename can quietly break, in the direction that matters: a name that still
## matches must still paint.
func test_a_runs_deepest_biome_row_takes_that_biomes_colour() -> void:
	var def: BiomeDef = App.biomes.biomes[0]
	var stats := App.stats_data
	var before: Array = stats.runs.duplicate()
	stats.add_run({"index": 1, "deepest_biome": def.display_name})

	await _open(_panel.btn_runs)
	var tinted := false
	for card in _content().get_children():
		for row in card.rows.get_children():
			if row.lbl_label.text != "Deepest biome":
				continue
			var shader_material := row.icon.material as ShaderMaterial
			assert_object(shader_material.get_shader_parameter(&"icon_color")) \
				.is_equal(def.biome_color)
			tinted = true
	assert_bool(tinted).is_true()

	stats.runs = before

func _row_icon_color(label: String) -> Color:
	for row in _content().get_children():
		if row.lbl_label.text == label:
			var shader_material := row.icon.material as ShaderMaterial
			return shader_material.get_shader_parameter(&"icon_color")
	return Color.TRANSPARENT

## All three layers of _color_for(), each on a row where that layer is the only
## one that gives the right answer.
##
## Nutrients rather than crystals for the currency case: the Crystal Caves accent
## and the crystal CurrencyDef are the same colour to the byte, so a crystal row
## passes whichever layer painted it and proves neither.
func test_records_rows_take_their_currency_or_biome_colour() -> void:
	var nutrients: CurrencyDef = load("res://data/currencies/res_nutrients_def.tres")
	assert_object(_row_icon_color("Most nutrients held")).is_equal(nutrients.main_color)

	# No currency counts nodes, so this one falls through to the screen that owns
	# them, which carries Meadow's colour.
	var nodes: ScreenDefinition = App.screens_data.screen_data.get(ScreenTypes.Types.NODES)
	assert_object(_row_icon_color("Most nodes grown")).is_equal(nodes.accent_color)

	# Fertilizer resolves the same way now that it has a def of its own, and no
	# screen lists it - so this one only passes through the registry, never
	# through the screen fallback.
	var fertilizer: CurrencyDef = App.currencies.currencies.get(
		CurrencyTypes.Types.FERTILIZER)
	assert_object(_row_icon_color("Most fertilizer held")).is_equal(fertilizer.main_color)

	# Belongs to no biome at all - a sheet that opens over any of them.
	assert_object(_row_icon_color("Playing since")).is_equal(StatIcons.ROW_COLOR)
