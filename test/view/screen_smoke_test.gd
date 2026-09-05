extends GdUnitTestSuite
## Every screen scene instantiates, runs a frame and tears down cleanly.
##
## Shallow on purpose: it asserts nothing about what a screen looks like. What it
## catches is the class of breakage a parse check cannot - an @export left
## dangling after a node was renamed, a _ready() that reaches for a ViewModel
## that no longer exposes what it wants, a signal connected in _ready() and
## disconnected in _exit_tree() where only one of the two was updated.
##
## Those are exactly the failures that otherwise surface as a blank tab in a
## build, so a boot-and-free is worth its runtime.

const SCREENS: Array[String] = [
	"res://view/biomes/sc_biomes.tscn",
	"res://view/mycelium_node/sc_nodes_panel.tscn",
	"res://view/prestige/sc_prestige.tscn",
	"res://view/crystal_caves/sc_crystal_caves.tscn",
	"res://view/well/sc_well.tscn",
	"res://view/ruins/sc_ruins.tscn",
	"res://view/boosts/sc_boosts.tscn",
	"res://view/achievements/sc_achievements_panel.tscn",
	"res://view/statistics/sc_statistics_panel.tscn",
	"res://view/growth/sc_growth_panel.tscn",
	"res://view/fertilizer/sc_fertilizer_panel.tscn",
	"res://view/offline_income/sc_offline_income.tscn",
	"res://view/main/sc_top_bar.tscn",
	"res://view/navigation/sc_nav_disc.tscn",
	"res://view/navigation/sc_nav_menu.tscn",
	"res://view/navigation/sc_nav_sub_bar.tscn",
	"res://view/resource_bar/sc_resource_bar.tscn",
]

func test_every_screen_boots_and_frees() -> void:
	for path in SCREENS:
		var packed: PackedScene = load(path)
		assert_object(packed).override_failure_message(
			"%s failed to load" % path).is_not_null()

		var screen: Node = packed.instantiate()
		add_child(screen)
		await get_tree().process_frame

		assert_bool(is_instance_valid(screen)).override_failure_message(
			"%s did not survive its first frame" % path).is_true()

		# Freed rather than auto_free()'d: _exit_tree() is half of what this
		# suite is here to exercise, and it only runs on an actual removal.
		remove_child(screen)
		screen.free()

## Leaving and re-entering a screen is the real navigation pattern - GameScreens
## frees the outgoing screen and instantiates the incoming one on every tab
## press. A connect in _ready() without its disconnect in _exit_tree() survives
## one boot and throws on the second.
func test_screens_survive_being_reopened() -> void:
	for path in SCREENS:
		var packed: PackedScene = load(path)
		for i in range(3):
			var screen: Node = packed.instantiate()
			add_child(screen)
			await get_tree().process_frame
			remove_child(screen)
			screen.free()
		assert_bool(true).override_failure_message(
			"%s did not survive being reopened" % path).is_true()
