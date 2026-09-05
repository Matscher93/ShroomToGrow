extends GdUnitTestSuite
## Unit tests for StatIcons (view/icons/gd_stat_icons.gd).
##
## The mapping is keyed on stat names that live in .tres files, so a stat renamed
## on one side and not the other fails silently: for_stat() falls through to its
## nutrients default and the row draws a leaf next to a water number, with
## nothing reported. These assertions are the only thing that catches it.

func test_the_two_water_stats_are_told_apart() -> void:
	# Pumping harder and pumping more often are different decisions, so the icon
	# column has to distinguish them - it is the water rows where a shared droplet
	# said the least.
	assert_int(StatIcons.for_stat(&"water_production")).is_equal(StatIcons.Icon.WATER)
	assert_int(StatIcons.for_stat(&"water_rate")).is_equal(StatIcons.Icon.WATER_RATE)

func test_the_permanent_tracks_draw_their_own_currency() -> void:
	assert_int(StatIcons.for_stat(&"biomass_gain")).is_equal(StatIcons.Icon.BIOMASS)

func test_the_two_rate_stats_are_told_apart() -> void:
	assert_int(StatIcons.for_stat(&"tick_rate")).is_equal(StatIcons.Icon.TEMPO)
	assert_int(StatIcons.for_stat(&"automation_rate")).is_equal(StatIcons.Icon.AUTOMATION)

func test_no_two_mapped_stats_share_an_icon() -> void:
	# The icon column is only worth its width while each stat has its own shape.
	# A stat added with a copy-pasted branch is the way that quietly stops being
	# true, and nothing on screen would say so.
	var seen := {}
	for stat: StringName in [&"node_production", &"water_production", &"water_rate",
			&"biomass_gain", &"tick_rate", &"automation_rate",
			&"boost_max_level", &"boost_power"]:
		var icon := StatIcons.for_stat(stat)
		assert_bool(seen.has(icon)) \
			.override_failure_message("'%s' draws the same icon as '%s'." \
				% [stat, seen.get(icon, &"")]).is_false()
		seen[icon] = stat

func test_the_two_crystal_boost_stats_are_told_apart() -> void:
	# One widens a boost's ladder, the other makes each of its rungs hit harder.
	# Both are about the same boost, and neither is the bare crystal cluster that
	# stands for crystals themselves.
	assert_int(StatIcons.for_stat(&"boost_max_level")).is_equal(StatIcons.Icon.BOOST_CEILING)
	assert_int(StatIcons.for_stat(&"boost_power")).is_equal(StatIcons.Icon.BOOST_POWER)

func test_production_and_anything_unmapped_draw_nutrients() -> void:
	assert_int(StatIcons.for_stat(&"node_production")).is_equal(StatIcons.Icon.NUTRIENTS)
	assert_int(StatIcons.for_stat(&"not_a_stat")).is_equal(StatIcons.Icon.NUTRIENTS)

func test_every_authored_project_boon_maps_to_a_drawable_icon() -> void:
	# sh_stat_icon.gdshader branches on the ordinal and returns an empty mask for
	# anything past its last branch, so an icon id it has no case for renders as a
	# blank square rather than as an error.
	var drawable := StatIcons.Icon.size()
	var projects := (load("res://data/well/all_projects.tres") as ProjectList).projects
	for project in projects:
		for boon in project.boons:
			assert_int(StatIcons.for_stat(boon.effect.stat)) \
				.override_failure_message("Project '%s' boon '%s' maps to an icon the shader cannot draw." \
					% [project.id, boon.display_name]).is_less(drawable)
