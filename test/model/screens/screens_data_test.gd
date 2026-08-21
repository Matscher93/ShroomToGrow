extends GdUnitTestSuite
## Unit tests for ScreensData (model/screens/gd_screens_data.gd).
##
## The whole model is one guarded setter, and that guard is what stops every
## bound view rebuilding itself on a tab press that changed nothing.

var _emitted: Array[int]

func before_test() -> void:
	_emitted = [0]

func _registry() -> Dictionary[ScreenTypes.Types, ScreenDefinition]:
	var registry: Dictionary[ScreenTypes.Types, ScreenDefinition] = {}
	return registry

func _data(initial: ScreenTypes.Types) -> ScreensData:
	var data := ScreensData.new(_registry(), initial)
	var emitted := _emitted
	data.screen_changed.connect(func(_screen: ScreenTypes.Types) -> void: emitted[0] += 1)
	return data

func test_starts_on_the_initial_screen() -> void:
	assert_int(_data(ScreenTypes.Types.NODES).current_screen).is_equal(ScreenTypes.Types.NODES)

func test_switching_screens_notifies_once() -> void:
	var data := _data(ScreenTypes.Types.BIOMES)
	data.current_screen = ScreenTypes.Types.PRESTIGE
	assert_int(data.current_screen).is_equal(ScreenTypes.Types.PRESTIGE)
	assert_int(_emitted[0]).is_equal(1)

func test_reselecting_the_current_screen_is_silent() -> void:
	# Views respawn on screen_changed (see the "returned to respawning UIs"
	# change), so re-emitting for the tab already open throws the live screen
	# away and rebuilds it for nothing.
	var data := _data(ScreenTypes.Types.BIOMES)
	data.current_screen = ScreenTypes.Types.BIOMES
	assert_int(_emitted[0]).is_zero()

func test_switching_back_and_forth_notifies_each_way() -> void:
	var data := _data(ScreenTypes.Types.BIOMES)
	data.current_screen = ScreenTypes.Types.NODES
	data.current_screen = ScreenTypes.Types.BIOMES
	assert_int(_emitted[0]).is_equal(2)

func test_the_screen_registry_is_exposed_as_given() -> void:
	var definition := ScreenDefinition.new()
	var registry := _registry()
	registry[ScreenTypes.Types.NODES] = definition

	var data := ScreensData.new(registry, ScreenTypes.Types.NODES)

	assert_int(data.screen_data.size()).is_equal(1)
	assert_object(data.screen_data[ScreenTypes.Types.NODES]).is_same(definition)

## The nav menu taps a sub-view row and expects to land on that screen showing
## that sub-view. Both halves come out of one call so a view never has to
## sequence the two writes itself.
func test_select_emits_the_sub_request_before_the_screen_change() -> void:
	var data := _data(ScreenTypes.Types.BIOMES)
	var order: Array[String] = []
	data.sub_screen_requested.connect(
		func(_screen: ScreenTypes.Types, _index: int) -> void: order.append("sub"))
	data.screen_changed.connect(
		func(_screen: ScreenTypes.Types) -> void: order.append("screen"))

	data.select(ScreenTypes.Types.CRYSTAL_CAVES, 2)

	# The screen is spawned synchronously off screen_changed and reads its
	# remembered sub-view in _ready(), so the sub request has to land first or
	# the screen opens on the old tab and corrects itself a frame later.
	assert_array(order).is_equal(["sub", "screen"])
	assert_int(data.current_screen).is_equal(ScreenTypes.Types.CRYSTAL_CAVES)

## The guarded setter stays silent for the screen already up, but the sub-view
## still has to move - that is the whole point of tapping a sub-row from the
## screen it belongs to.
func test_select_still_requests_a_sub_view_on_the_current_screen() -> void:
	var data := _data(ScreenTypes.Types.CRYSTAL_CAVES)
	var requested: Array[int] = []
	data.sub_screen_requested.connect(
		func(_screen: ScreenTypes.Types, index: int) -> void: requested.append(index))

	data.select(ScreenTypes.Types.CRYSTAL_CAVES, 1)

	assert_array(requested).is_equal([1])
	assert_int(_emitted[0]).is_zero()

## A top-level row leaves the target screen on whatever sub-view it remembers.
func test_select_without_a_sub_index_requests_nothing() -> void:
	var data := _data(ScreenTypes.Types.BIOMES)
	var requested: Array[int] = []
	data.sub_screen_requested.connect(
		func(_screen: ScreenTypes.Types, index: int) -> void: requested.append(index))

	data.select(ScreenTypes.Types.NODES)

	assert_array(requested).is_empty()
	assert_int(_emitted[0]).is_equal(1)
