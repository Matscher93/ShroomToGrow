class_name ScreenTypes
extends RefCounted

## Append only: the ordinal is the dictionary key in all_screens.tres.
enum Types {BIOMES, NODES, PRESTIGE, CRYSTAL_CAVES, WELL}

## Bottom-bar tab order GameScreens._rebuild_nav_buttons() iterates. Kept apart
## from the enum because the ordinals are save/resource keys and cannot move.
## Every type has to be listed here or its tab never shows up.
const NAV_ORDER: Array[Types] = [
	Types.BIOMES,
	Types.NODES,
	Types.CRYSTAL_CAVES,
	Types.WELL,
	Types.PRESTIGE,
]
