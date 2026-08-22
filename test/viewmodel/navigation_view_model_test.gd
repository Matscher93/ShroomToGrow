extends GdUnitTestSuite
## Unit tests for NavigationViewModel (viewmodel/gd_navigation_view_model.gd).
##
## The menu is built entirely from what this hands out, and it is the only place
## the two rules that used to live in the bottom bar now live: which screens the
## player can reach, and which of a screen's sub-views belong in the list.
##
## Driven through the live App autoload, because that is what the VM reads.

var _vm: NavigationViewModel

func before_test() -> void:
	_vm = NavigationViewModel.new()

func after_test() -> void:
	_vm.dispose()

func _destination(type: ScreenTypes.Types) -> NavDestination:
	for row in _vm.destinations:
		if row.screen_type == type:
			return row
	return null

# ─── The list itself ─────────────────────────────────────────────────────────

## Biomes is always reachable: it is the screen every other one unlocks from.
func test_the_starting_screen_is_always_listed() -> void:
	assert_object(_destination(ScreenTypes.Types.BIOMES)).is_not_null()

## Locked screens are left out rather than shown greyed - they unlock from the
## biome cards, so a dead row here would point at nothing the player can act on.
func test_only_unlocked_screens_are_listed() -> void:
	for row in _vm.destinations:
		assert_bool(App.is_screen_unlocked(row.screen_type)).override_failure_message(
			"screen %d is listed but not unlocked" % row.screen_type).is_true()

func test_destinations_follow_nav_order() -> void:
	var listed: Array[int] = []
	for row in _vm.destinations:
		listed.append(ScreenTypes.NAV_ORDER.find(row.screen_type))
	var sorted := listed.duplicate()
	sorted.sort()
	assert_array(listed).is_equal(sorted)

## Every row paints itself from these, and a missing one is a blank icon or a
## black accent rather than a crash - so nothing else would catch it.
func test_every_row_carries_what_it_needs_to_paint() -> void:
	for row in _vm.destinations:
		assert_str(row.label).override_failure_message(
			"screen %d has no name" % row.screen_type).is_not_empty()
		assert_str(row.subtitle).override_failure_message(
			"screen %d has no subtitle" % row.screen_type).is_not_empty()
		assert_object(row.icon_shader).override_failure_message(
			"screen %d has no icon shader" % row.screen_type).is_not_null()
		assert_float(row.accent.a).override_failure_message(
			"screen %d has a transparent accent" % row.screen_type).is_greater(0.0)

func test_exactly_one_row_is_marked_current() -> void:
	var current := 0
	for row in _vm.destinations:
		if row.is_current:
			current += 1
	assert_int(current).is_equal(1)

func test_the_current_row_is_the_screen_that_is_up() -> void:
	var row := _destination(App.screens_data.current_screen)
	assert_object(row).is_not_null()
	assert_bool(row.is_current).is_true()
	assert_str(_vm.current_label).is_equal(row.label.to_upper())
	assert_object(_vm.current_accent).is_equal(row.accent)

# ─── Sub rows ────────────────────────────────────────────────────────────────

## A row only ever lists sub-views its own ScreenDefinition authors.
##
## Was "Crystals is the only screen with sub-views", which stopped being true the
## moment the Ruins arrived with three tabs of its own. Checking against the
## authored list instead says the same thing - no screen grew rows it does not
## own - without having to be edited every time a screen gains tabs.
func test_every_sub_row_is_one_its_screen_authors() -> void:
	for row in _vm.destinations:
		var definition: ScreenDefinition = App.screens_data.screen_data.get(row.screen_type)
		assert_object(definition).is_not_null()
		var authored: Array[String] = []
		for sub in definition.sub_screens:
			authored.append(sub.display_name)
		for sub in row.subs:
			assert_array(authored).override_failure_message(
				"screen %d lists sub row '%s', which it does not author." \
					% [row.screen_type, sub.label]).contains([sub.label])

## The gate the Ruins screen puts on its Creatures tab, checked the same way the
## Boosts one below is: before the first creature is within reach the tab is a
## page of locked cards, so a row leading to it would lead somewhere not on
## screen.
func test_the_creatures_sub_row_follows_the_creatures_tab() -> void:
	var row := _destination(ScreenTypes.Types.RUINS)
	if row == null:
		return
	var listed := false
	for sub in row.subs:
		if sub.label == "Creatures":
			listed = true
	assert_bool(listed).is_equal(App.ruins_vm.creatures_visible)

## The same gate the screen puts on the tab itself. Before the first boost perk
## the Boosts tab is hidden, so a row leading to it would lead somewhere that is
## not on screen.
func test_the_boosts_sub_row_follows_the_boosts_tab() -> void:
	var row := _destination(ScreenTypes.Types.CRYSTAL_CAVES)
	if row == null:
		return
	var listed := false
	for sub in row.subs:
		if sub.label == "Boosts":
			listed = true
	assert_bool(listed).is_equal(App.crystal_caves_vm.boosts_visible)

## A sub row's tab_index is handed straight to the TabContainer, so an index
## past the end would silently land the player on the wrong tab.
func test_sub_rows_point_at_real_tabs() -> void:
	var row := _destination(ScreenTypes.Types.CRYSTAL_CAVES)
	if row == null:
		return
	for sub in row.subs:
		assert_str(App.crystal_caves_vm.tab_label(sub.tab_index)).override_failure_message(
			"'%s' points at tab %d, which has no name" % [sub.label, sub.tab_index]
			).is_not_empty()

# ─── Badges ──────────────────────────────────────────────────────────────────

## The counts are what surface claimable work from across the game, so they have
## to agree with the cards the player would actually find on arriving.
func test_badge_counts_match_the_affordable_cards() -> void:
	var boosts := 0
	for vm: Variant in App.boost_vms.values():
		if vm.is_unlocked and vm.can_buy:
			boosts += 1
	var automations := 0
	for vm: Variant in App.automation_vms.values():
		if vm.is_unlocked and vm.can_buy:
			automations += 1

	assert_int(_vm.badge_count(SubScreenDefinition.BadgeSource.AFFORDABLE_BOOSTS)).is_equal(boosts)
	assert_int(_vm.badge_count(SubScreenDefinition.BadgeSource.AFFORDABLE_AUTOMATIONS)) \
		.is_equal(automations)

func test_a_row_without_a_badge_source_counts_nothing() -> void:
	assert_int(_vm.badge_count(SubScreenDefinition.BadgeSource.NONE)).is_zero()

# ─── Commands ────────────────────────────────────────────────────────────────

func test_go_to_switches_the_screen() -> void:
	var before := App.screens_data.current_screen
	_vm.go_to(ScreenTypes.Types.BIOMES)
	assert_int(App.screens_data.current_screen).is_equal(ScreenTypes.Types.BIOMES)
	App.screens_data.current_screen = before

func test_go_to_with_a_sub_index_moves_the_screens_sub_view() -> void:
	var before_screen := App.screens_data.current_screen
	var before_tab := App.crystal_caves_vm.current_tab

	_vm.go_to(ScreenTypes.Types.CRYSTAL_CAVES, 2)

	assert_int(App.screens_data.current_screen).is_equal(ScreenTypes.Types.CRYSTAL_CAVES)
	assert_int(App.crystal_caves_vm.current_tab).is_equal(2)

	App.screens_data.current_screen = before_screen
	App.crystal_caves_vm.current_tab = before_tab
