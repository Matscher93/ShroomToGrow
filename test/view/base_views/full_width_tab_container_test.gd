extends GdUnitTestSuite
## Unit tests for FullWidthTabContainer (view/base_views/gd_full_width_tab_container.gd).
##
## The padding it writes is what sets the tab bar's width, so the one thing that
## has to hold is that the measurement it computes the padding *from* cannot be
## moved by writing it. When that stopped holding, hiding a tab put the game in
## an endless layout loop - a hard lock, caught in the wild by the freeze
## watchdog on the Crystal Caves screen, whose Boosts and Sequences tabs are
## hidden until their perks are bought.
##
## Hosted in a SubViewport because the runner's root viewport is 64x64, and the
## bug only appears once there is real width for the padding to climb through.

const VIEWPORT_SIZE := Vector2i(660, 400)
const TAB_TITLES: Array[String] = ["Automations", "Boosts", "Sequences"]

var _viewport: SubViewport
var _tabs: FullWidthTabContainer

func before_test() -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	add_child(_viewport)
	_tabs = FullWidthTabContainer.new()
	_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	# As the Crystal Caves and Ruins screens have it: the nav menu switches these
	# tabs, so the bar itself is hidden. That is what makes the feedback vicious -
	# a hidden bar is never stretched to the container, so it sits at its own
	# minimum width, and that minimum is exactly what the padding below sets.
	_tabs.tabs_visible = false
	for title in TAB_TITLES:
		var page := Control.new()
		page.name = title
		_tabs.add_child(page)
	_viewport.add_child(_tabs)
	await get_tree().process_frame
	await get_tree().process_frame

func after_test() -> void:
	remove_child(_viewport)
	_viewport.free()

## The failure mode itself: with a tab hidden the bar is narrower than the
## container, which is the gap the old measurement climbed through. Two frames
## with the same bar width is the settle the loop never reached.
func test_hiding_a_tab_settles_within_a_frame() -> void:
	_tabs.set_tab_hidden(1, true)
	_tabs.spread_tabs()
	await get_tree().process_frame
	var settled := _tabs.get_tab_bar().size.x
	await get_tree().process_frame
	assert_float(_tabs.get_tab_bar().size.x).is_equal_approx(settled, 0.5)

## The loop itself, at the size it starts: writing the padding resizes the bar,
## which calls straight back in here, so one hidden tab has to settle in a single
## write. Measured against the bar it took a second, and a third, and did not
## stop - the cascade is the freeze, and the count is what sees it before the
## per-frame cap swallows it.
func test_hiding_a_tab_writes_the_padding_once() -> void:
	await get_tree().process_frame
	_tabs.set_tab_hidden(1, true)
	_tabs.spread_tabs()
	assert_int(_tabs._writes_this_frame).is_less_equal(1)

## The invariant behind it: the padding is a function of a width it does not
## move, so asking again answers the same. A second write here is the loop.
func test_spreading_twice_writes_the_same_padding() -> void:
	_tabs.set_tab_hidden(1, true)
	_tabs.spread_tabs()
	await get_tree().process_frame
	var applied := _tabs._applied_margin
	_tabs.spread_tabs()
	assert_float(_tabs._applied_margin).is_equal_approx(applied, 0.001)
	assert_float(applied).is_greater(0.0)

## Showing it again is the same move in reverse, and the padding has to come
## back down rather than keep the width it took while the tab was gone.
func test_showing_a_tab_again_settles_narrower() -> void:
	_tabs.set_tab_hidden(1, true)
	_tabs.spread_tabs()
	await get_tree().process_frame
	var with_two := _tabs._applied_margin
	_tabs.set_tab_hidden(1, false)
	_tabs.spread_tabs()
	await get_tree().process_frame
	assert_float(_tabs._applied_margin).is_less(with_two)

## The padded row is measured against the container, so it stays inside it
## however many tabs are showing.
func test_padded_titles_fit_the_container() -> void:
	for hidden in [0, 1, 2]:
		_tabs.set_tab_hidden(1, hidden == 1)
		_tabs.set_tab_hidden(2, hidden == 2)
		_tabs.spread_tabs()
		await get_tree().process_frame
		var bar := _tabs.get_tab_bar()
		var shown := 0
		var titles := 0.0
		var font := bar.get_theme_font(&"font")
		var font_size := bar.get_theme_font_size(&"font_size")
		for i in range(bar.tab_count):
			if bar.is_tab_hidden(i):
				continue
			shown += 1
			titles += font.get_string_size(bar.get_tab_title(i),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var gaps := float(bar.get_theme_constant(&"tab_separation") * (shown - 1))
		var row := titles + gaps + _tabs._applied_margin * float(shown * 2)
		assert_float(row).is_less_equal(_tabs.size.x)
