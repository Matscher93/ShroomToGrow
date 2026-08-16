class_name StatIcons
extends RefCounted
## VIEW: which icon stands for the area a stat belongs to.
##
## Static helper namespace, no state. Lives beside sh_stat_icon.gdshader because
## the ordinals below *are* that shader's icon_id branches - the same contract
## CurrencyTypes documents for the resource pill.
##
## Every lever gets its own shape. The two rate stats in particular: a boon that
## makes the well pump harder and one that makes it pump more often both move
## water, but they are different decisions, and a shared droplet made the row's
## icon column carry no information on the rows where it mattered most.

## Append only: the ordinal is the icon_id branch in sh_stat_icon.gdshader.
enum Icon {NUTRIENTS, WATER, BIOMASS, CRYSTALS, TEMPO, WATER_RATE, AUTOMATION,
	BOOST_CEILING, BOOST_POWER}

## Falls back to nutrients, the area every run has from its first tick, so a stat
## added without a matching icon draws something rather than an empty square.
static func for_stat(stat: StringName) -> Icon:
	match stat:
		&"water_production":
			return Icon.WATER
		&"water_rate":
			return Icon.WATER_RATE
		&"biomass_gain":
			return Icon.BIOMASS
		&"crystal_gain":
			return Icon.CRYSTALS
		&"tick_rate":
			return Icon.TEMPO
		&"automation_rate":
			return Icon.AUTOMATION
		&"boost_max_level":
			return Icon.BOOST_CEILING
		&"boost_power":
			return Icon.BOOST_POWER
		_:
			return Icon.NUTRIENTS
