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

## What a row icon paints when nothing more specific applies - the statistics
## overlay's own accent, so a column of them reads as one column.
##
## Lives here rather than on either of the two scenes that draw an icon: the row,
## the card and the panel that tints one row against a biome all need the same
## value, and a third copy is a third place for it to drift. The materials in
## sc_stat_row.tscn and sc_stat_card.tscn carry it a fourth time because a
## .tscn cannot reference a const - those are the authored defaults, overwritten
## on the first set_icon().
const ROW_COLOR := Color(0.36078432, 0.78431374, 0.9019608, 1)

## Append only: the ordinal is the icon_id branch in sh_stat_icon.gdshader.
##
## The first nine are the boon areas for_stat() maps to. Everything after them is
## addressed by name instead - the statistics overlay's rows count things that
## are not stats at all (a streak, a sporation, how long a save has been played),
## so its own table picks those. One dispatcher either way: a second shader over
## a second id space would mean two places to add the next icon to.
enum Icon {NUTRIENTS, WATER, BIOMASS, CRYSTALS, TEMPO, WATER_RATE, AUTOMATION,
	BOOST_CEILING, BOOST_POWER,
	RELICS, ICHOR, GLYPHS, FERTILIZER, TIME, NODE, BIOME, LEVEL, SYMBIOSIS,
	PERK, STREAK, EVENT, SPORE}

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
