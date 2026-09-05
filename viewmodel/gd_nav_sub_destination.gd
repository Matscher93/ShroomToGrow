class_name NavSubDestination
extends RefCounted
## VIEWMODEL: one indented row under a NavDestination - a sub-view of that
## screen, reachable in a single tap from anywhere.
##
## accent is the parent's: a sub-row belongs to its screen's identity and has
## none of its own.

var screen_type: ScreenTypes.Types
var label: String
var tab_index: int
var accent: Color
var is_current: bool
var badge_count: int
## Kept alongside the count so an open menu can re-read it when currency moves,
## instead of rebuilding every row to pick up a new number.
var badge_source: BadgeSource.Source
