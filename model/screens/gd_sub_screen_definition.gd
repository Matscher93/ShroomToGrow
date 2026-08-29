class_name SubScreenDefinition
extends Resource
## MODEL: one sub-view of a screen, surfaced as an indented row under its parent
## in the nav menu. Parallel to ScreenDefinition, one level down.
##
## tab_index is the child index inside that screen's TabContainer, which is what
## the screen's ViewModel already stores as its remembered tab.

## Which live count the row's badge shows, if any. Sub-views are too few and too
## unalike for a generic "count" hook to be worth it, so each one names the
## number it wants and NavigationViewModel does the counting.
enum BadgeSource { NONE, AFFORDABLE_BOOSTS, AFFORDABLE_AUTOMATIONS,
	COLLECTABLE_MISSIONS, AFFORDABLE_MISSION_BOOSTS }

## When the row belongs in the menu at all. A sub-view that its screen hides is a
## row leading somewhere that is not on screen, so the two gates have to agree.
enum VisibleWhen { ALWAYS, BOOSTS_UNLOCKED, HEROES_UNLOCKED }

@export var display_name: String
@export var tab_index: int
@export var badge_source: BadgeSource = BadgeSource.NONE
@export var visible_when: VisibleWhen = VisibleWhen.ALWAYS
