extends GdUnitTestSuite
## The three shader-panel buttons, driven through their real .tscn files.
##
## They share gd_base_shader_button.gd, which carries the press tracking, the
## text setter and the re-emitted `pressed`; each subclass only overrides
## _state_color() and its modulate. That split is invisible in a parse check -
## a subclass that forgets to call _bind_button() still compiles, still paints,
## and silently stops responding to presses.
##
## Loading the scenes rather than building nodes by hand is the point: it is also
## what proves the exported `color_param` and `button_color` still deserialize
## now that they are inherited from the base rather than declared per script.

## _ready() runs on the frame after add_child, and _bind_button() lives in it, so
## every test has to let the node draw breath before poking it.
##
## Typed Control rather than Node because the shader lookup below reads
## `material`, a CanvasItem property. auto_free() returns Variant, so the local
## needs an explicit type rather than `:=`.
func _spawn(scene_path: String) -> Control:
	var node: Control = auto_free((load(scene_path) as PackedScene).instantiate())
	add_child(node)
	await get_tree().process_frame
	return node

func _fill(node: Control) -> Variant:
	var shader_material := node.material as ShaderMaterial
	return shader_material.get_shader_parameter(node.color_param) if shader_material else null

# ─── Shared base behaviour ───────────────────────────────────────────────────

func test_the_exported_shader_params_survive_being_inherited() -> void:
	for path in ["res://view/main/sc_screen_button.tscn",
			"res://view/offline_income/sc_collect_offline_income_button.tscn"]:
		var node: Control = await _spawn(path)
		assert_str(node.color_param).override_failure_message(
			"%s lost its color_param" % path).is_not_empty()
		assert_object(_fill(node)).override_failure_message(
			"%s paints nothing" % path).is_not_null()

func test_the_wrapped_button_resolves() -> void:
	var node: Control = await _spawn("res://view/main/sc_screen_button.tscn")
	assert_object(node._wrapped_button()).is_not_null()

func test_setting_the_text_reaches_the_wrapped_button() -> void:
	var node: Control = await _spawn("res://view/main/sc_screen_button.tscn")
	node.set_button_text("Caves")
	assert_str(node._button.text).is_equal("Caves")

## Regression: GameScreens._rebuild_nav_buttons() captions each tab and sets its
## selection *before* add_child(), so every setter has to work on a node whose
## _ready() has not run. A version of the base that cached the wrapped Button in
## _ready() made this a silent no-op and every tab kept the scene's placeholder
## caption.
func test_the_setters_work_before_the_button_enters_the_tree() -> void:
	for path in ["res://view/main/sc_screen_button.tscn",
			"res://view/offline_income/sc_collect_offline_income_button.tscn"]:
		var node: Control = auto_free((load(path) as PackedScene).instantiate())
		# Deliberately no add_child and no awaited frame.
		node.set_button_text("Caves")
		assert_str(node._wrapped_button().text).override_failure_message(
			"%s dropped its caption when set before entering the tree" % path
			).is_equal("Caves")

## Views bind to this exactly as they would a plain Button's, so it has to fire
## from the wrapped Button's release.
func test_the_wrapped_buttons_release_is_re_emitted() -> void:
	var node: Control = await _spawn("res://view/main/sc_screen_button.tscn")
	var fired: Array[int] = [0]
	node.pressed.connect(func() -> void: fired[0] += 1)
	node._button.button_up.emit()
	assert_int(fired[0]).is_equal(1)

func test_press_state_tracks_the_wrapped_button() -> void:
	var node: Control = await _spawn("res://view/main/sc_screen_button.tscn")
	node._button.button_down.emit()
	assert_bool(node.is_button_pressed).is_true()
	node._button.button_up.emit()
	assert_bool(node.is_button_pressed).is_false()

# ─── Per-subclass state colours ──────────────────────────────────────────────

func test_screen_button_paints_its_selected_state() -> void:
	var node: Control = await _spawn("res://view/main/sc_screen_button.tscn")

	node.set_selected(true)
	assert_object(_fill(node)).is_equal(node.button_selected_color)
	assert_object(node.modulate).is_equal(Color.WHITE)

	node.set_selected(false)
	assert_object(_fill(node)).is_equal(node.button_color)
	assert_object(node.modulate).is_equal(Color.GRAY)

## Driven off the wrapped Button's own `disabled`, not a flag of its own.
func test_collect_button_paints_its_disabled_state() -> void:
	var node: Control = await _spawn("res://view/offline_income/sc_collect_offline_income_button.tscn")

	node.set_disabled(true)
	assert_object(_fill(node)).is_equal(node.disabled_color)

	node.set_disabled(false)
	assert_object(_fill(node)).is_equal(node.button_color)

func test_buy_button_darkens_and_dims_when_disabled() -> void:
	var panel: Control = await _spawn("res://view/mycelium_node/sc_mycelium_node_panel.tscn")
	var node: Control = panel.find_child("panel_buy_node", true, false)
	assert_object(node).is_not_null()

	node.set_enabled(true)
	assert_object(_fill(node)).is_equal(node.button_color)
	assert_object(node.modulate).is_equal(Color.WHITE)
	assert_bool(node.upgrade_button.disabled).is_false()

	node.set_enabled(false)
	assert_object(_fill(node)).is_equal(node.button_color.darkened(0.70))
	assert_object(node.modulate).is_equal(Color(0.3, 0.3, 0.3))
	assert_bool(node.upgrade_button.disabled).is_true()
