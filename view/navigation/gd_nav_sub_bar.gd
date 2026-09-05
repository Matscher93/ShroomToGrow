extends HBoxContainer
## VIEW: the sub-view chips beside the menu disc. One chip per sub-view of the
## screen that is up, tappable with the menu closed.
##
## The menu popout owns navigation *between* screens; this row is the move inside
## one - the tab switch a player makes far more often than a screen change, and
## the one the popout made cost an open, a scroll and a tap. Nothing here can
## reach a screen the menu cannot: the chips are built from the same
## NavSubDestination rows the menu's sub-rows are.
##
## Lives beside the disc rather than inside the popout, so it is on screen for
## the whole session rather than spawned per open - which is why this binds the
## ViewModel live instead of taking a snapshot the way the menu's rows do.

const CHIP_SCENE := preload("res://view/navigation/sc_nav_sub_chip.tscn")

var _vm: NavigationViewModel
## The chips on screen, in order. Tracked rather than read off get_children(),
## which also holds the guard.
var _chips: Array[Control] = []
## Badge sources paired with _chips by index, so a currency change repaints the
## numbers without rebuilding the row under the player's finger - same reason the
## menu keeps its own list.
var _badge_sources: Array[BadgeSource.Source] = []
## What the chips on screen were built from. Compared against the incoming rows
## to decide between re-binding and respawning - see _refresh_chips().
var _shown: PackedStringArray = PackedStringArray()
var _guard := PressGuard.new()

func _ready() -> void:
	add_child(_guard)
	bind(App.navigation_vm)

func bind(vm: NavigationViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_chips()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

## Both go through the guard, and neither can run inline.
##
## Tapping a chip calls go_to(), which reaches ScreensData.select(), which emits
## back into here while the chip's own `selected` emission is still on the stack -
## a rebuild there would free that chip out from under the handler running in it.
## And a refresh that lands between a press and its release swallows the tap
## outright, which is what the guard is for. See PressGuard.
func _on_property_changed(property: StringName) -> void:
	match property:
		NavigationViewModel.PROP_DESTINATIONS_CHANGED:
			_guard.run_when_free(&"chips", _refresh_chips, true)
		NavigationViewModel.PROP_BADGES_CHANGED:
			_guard.run_when_free(&"badges", _refresh_badges)

## Respawns only when the row set itself moved; otherwise re-binds the chips that
## are already up.
##
## Worth the comparison because most of what reaches here changed nothing about
## these chips: the prestige track invalidates its cache on every Biome Size
## bought, which is once a tick while an automation is running, and that arrives
## as an upgrades_changed the nav cannot tell from a perk purchase. Rebuilding on
## it threw away three identical chips a second. Same pattern as the events sheet.
func _refresh_chips() -> void:
	var subs := _vm.current_subs
	var signature := _signature(subs)
	if signature == _shown:
		for i in subs.size():
			_chips[i].bind(subs[i])
		return

	_shown = signature
	for chip in _chips:
		remove_child(chip)
		chip.queue_free()
	_chips.clear()
	_badge_sources.clear()

	for sub in subs:
		var chip := CHIP_SCENE.instantiate()
		add_child(chip)
		chip.bind(sub)
		chip.selected.connect(_on_sub_selected)
		_chips.append(chip)
		_badge_sources.append(sub.badge_source)

## Everything a chip paints itself from except the badge count, which is pushed
## into the built chip instead - see _refresh_badges().
func _signature(subs: Array[NavSubDestination]) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in subs:
		out.append("%d|%d|%s|%s" % [sub.screen_type, sub.tab_index, sub.label, sub.is_current])
	return out

func _refresh_badges() -> void:
	for i in _chips.size():
		_chips[i].set_badge(_vm.badge_count(_badge_sources[i]))

func _on_sub_selected(screen_type: ScreenTypes.Types, tab_index: int) -> void:
	_vm.go_to(screen_type, tab_index)
