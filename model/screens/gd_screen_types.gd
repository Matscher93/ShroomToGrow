class_name ScreenTypes
extends RefCounted

## Append only: the ordinal is both the dictionary key in all_screens.tres and
## the bottom-bar tab order GameScreens._rebuild_nav_buttons() iterates.
enum Types {BIOMES, NODES, PRESTIGE, CRYSTAL_CAVES}
