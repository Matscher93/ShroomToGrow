class_name BadgeSource
extends RefCounted
## MODEL: which live count a nav row's badge shows, if any.
##
## Shared by ScreenDefinition and SubScreenDefinition: a screen with sub-views
## badges the sum of their rows, and one without names its own count here.
## Destinations are too few and too unalike for a generic "count" hook to be
## worth it, so each one names the number it wants and NavigationViewModel does
## the counting.
##
## Ordinals are stored as ints in the authored .tres screen definitions, so
## existing entries keep their meaning only as long as new sources are appended
## rather than inserted.

enum Source {
	NONE,
	AFFORDABLE_BOOSTS,
	AFFORDABLE_AUTOMATIONS,
	COLLECTABLE_MISSIONS,
	AFFORDABLE_MISSION_BOOSTS,
	## Biome cards waiting on the player - unspent points, or a locked biome
	## that just became affordable. See BiomeViewModel.has_attention.
	BIOME_ATTENTION,
	## Node tiers reached but never bought, and affordable now. See
	## MyceliumNodeViewModel.has_attention.
	NEW_NODE_TIER,
}
