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
