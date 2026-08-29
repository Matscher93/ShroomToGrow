class_name StatNames
extends RefCounted
## MODEL: every stat an effect can name, in one place.
##
## Effects, boosts and producers reach the systems that pay them out by plain
## StringName - never by reference - so a name no system reads is not an error
## at load, not a warning at runtime and not a visible symptom. The effect simply
## resolves to zero forever.
##
## That makes the set of readable names a real part of the domain rather than a
## test fixture, which is why it lives here: the integrity sweep asserts against
## it, and the balance editor offers it as a dropdown so a stat is picked instead
## of typed. Adding a stat means adding it here, in the same commit as the system
## that starts reading it.
##
## ProductionSystem consumes most of them; the exceptions carry a note.

const ALL: Array[StringName] = [
	&"potency_production", &"synergy_production", &"node_production",
	&"biomass_gain", &"tick_rate",
	# Read by BiomeSystem rather than ProductionSystem.
	&"biome_points",
	# Read by PlayerLevelSystem, the same way biome_points is read by BiomeSystem.
	&"level_points",
	&"crystal_gain", &"automation_rate",
	&"water_production", &"water_rate",
	# Read by BoostSystem rather than ProductionSystem: the Well's projects reach
	# a crystal boost's ceiling and its per-level rate through these.
	&"boost_max_level", &"boost_power",
	# The Ruins. farm_slots is read by MissionSystem and creature_rank_cap by
	# CreatureSystem, the same way biome_points is read by BiomeSystem; the rest
	# resolve through ProductionSystem like everything above.
	&"mission_speed", &"farm_slots", &"mission_reward",
	&"relic_gain", &"ichor_gain", &"glyph_gain", &"creature_rank_cap",
]


## True when some system actually reads this name. An effect naming anything else
## is inert.
static func is_known(stat: StringName) -> bool:
	return ALL.has(stat)
