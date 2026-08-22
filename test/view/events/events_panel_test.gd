extends GdUnitTestSuite
## The events overlay's scene wiring.
##
## Every @export on this panel and its card is a hand-written NodePath into a deep
## tree, and a wrong one is null at runtime with nothing to say so until a player
## opens the sheet. Mirrors what growth_panel_test does for the growth overlay.
##
## The one mutation here is a card pushed onto the live queue and taken off again
## in after_test, since the sheet has nothing to render otherwise. Nothing is
## collected or fulfilled, so no balance and no lifetime counter moves.

const PANEL := "res://view/events/sc_events_panel.tscn"

var _panel: Control
var _spawned: Array[int] = []

func before_test() -> void:
	_spawned.clear()
	_panel = (load(PANEL) as PackedScene).instantiate()
	add_child(_panel)
	await get_tree().process_frame

func after_test() -> void:
	# Freed rather than auto_free()'d: _exit_tree() disconnects the ViewModel and
	# only runs on an actual removal.
	remove_child(_panel)
	_panel.free()
	for instance_id in _spawned:
		App.events_data.remove(instance_id)

func _spawn(def_id: StringName, roll: int) -> int:
	var instance_id := App.events_data.add(def_id, roll)
	_spawned.append(instance_id)
	return instance_id

func test_every_exported_node_resolves() -> void:
	for property in ["btn_close", "lbl_count", "vbox_events", "panel_empty",
			"event_card_scene"]:
		assert_object(_panel.get(property)).override_failure_message(
			"events_panel.%s did not resolve." % property).is_not_null()

func test_the_placeholder_and_the_count_track_the_live_queue() -> void:
	var expected: int = App.events_data.count()
	assert_bool(_panel.panel_empty.visible).is_equal(expected == 0)
	assert_str(_panel.lbl_count.text).is_equal("%d / %d" % [expected, EventSystem.MAX_QUEUE])

## The queue changes length as events spawn and are answered, so unlike the growth
## sheet's fixed rows these are rebuilt on every notification.
func test_a_spawned_event_gets_a_card() -> void:
	var before: int = _panel.vbox_events.get_child_count()
	_spawn(&"spore_flush", 0)
	assert_int(_panel.vbox_events.get_child_count()).is_equal(before + 1)
	assert_bool(_panel.panel_empty.visible).is_false()

func test_every_exported_node_on_a_card_resolves() -> void:
	_spawn(&"spore_flush", 0)
	var card: Control = _panel.vbox_events.get_child(_panel.vbox_events.get_child_count() - 1)
	for property in ["color_rail", "color_dot", "lbl_eyebrow", "btn_skip", "lbl_title",
			"lbl_description", "btn_collect", "box_spend", "lbl_spend", "lbl_spend_reward",
			"btn_fulfil", "box_progress", "lbl_progress", "lbl_progress_reward",
			"bar_progress"]:
		assert_object(card.get(property)).override_failure_message(
			"event_card.%s did not resolve." % property).is_not_null()

## A card is a boon, a quest or a countdown for its whole life, and exactly one of
## the three bodies is ever up.
func test_a_boon_shows_only_the_collect_button() -> void:
	_spawn(&"spore_flush", 0)
	var card: Control = _panel.vbox_events.get_child(_panel.vbox_events.get_child_count() - 1)
	assert_bool(card.btn_collect.visible).is_true()
	assert_bool(card.box_spend.visible).is_false()
	assert_bool(card.box_progress.visible).is_false()
	assert_str(card.lbl_title.text).is_equal(App.event_def(&"spore_flush").title)

func test_a_spend_quest_shows_only_the_fulfil_row() -> void:
	_spawn(&"irrigation_pact", 3)
	var card: Control = _panel.vbox_events.get_child(_panel.vbox_events.get_child_count() - 1)
	assert_bool(card.btn_collect.visible).is_false()
	assert_bool(card.box_spend.visible).is_true()
	assert_bool(card.box_progress.visible).is_false()
	assert_str(card.lbl_spend_reward.text).is_equal("-> +3 fertilizer")

func test_a_progress_quest_shows_only_the_bar() -> void:
	_spawn(&"steady_cultivation", 3)
	var card: Control = _panel.vbox_events.get_child(_panel.vbox_events.get_child_count() - 1)
	assert_bool(card.btn_collect.visible).is_false()
	assert_bool(card.box_spend.visible).is_false()
	assert_bool(card.box_progress.visible).is_true()
	assert_str(card.lbl_progress.text).is_equal("0 / %d ticks"
		% App.event_def(&"steady_cultivation").goal_ticks)
