class_name ScreenTypes
extends RefCounted

## Append only: the ordinal is the dictionary key in all_screens.tres.
enum Types {BIOMES, NODES, PRESTIGE, CRYSTAL_CAVES, WELL}

## The order NavigationViewModel lists destinations in. Kept apart from the enum
## because the ordinals are save/resource keys and cannot move.
## Every type has to be listed here or it never shows up in the nav menu.
const NAV_ORDER: Array[Types] = [
	Types.BIOMES,
	Types.NODES,
	Types.CRYSTAL_CAVES,
	Types.WELL,
	Types.PRESTIGE,
]
