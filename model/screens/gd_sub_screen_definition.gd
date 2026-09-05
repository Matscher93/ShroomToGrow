class_name SubScreenDefinition
extends Resource
## MODEL: one sub-view of a screen, surfaced as an indented row under its parent
## in the nav menu. Parallel to ScreenDefinition, one level down.
##
## tab_index is the child index inside that screen's TabContainer, which is what
## the screen's ViewModel already stores as its remembered tab.

## When the row belongs in the menu at all. A sub-view that its screen hides is a
## row leading somewhere that is not on screen, so the two gates have to agree.
enum VisibleWhen { ALWAYS, BOOSTS_UNLOCKED, HEROES_UNLOCKED, SEQUENCES_UNLOCKED }

@export var display_name: String
@export var tab_index: int
## Which live count this row's badge shows. See BadgeSource, shared with the
## screen definition above it.
@export var badge_source: BadgeSource.Source = BadgeSource.Source.NONE
@export var visible_when: VisibleWhen = VisibleWhen.ALWAYS
