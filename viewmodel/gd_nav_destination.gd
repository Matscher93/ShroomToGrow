class_name NavDestination
extends RefCounted
## VIEWMODEL: one row of the nav menu, already resolved for display.
##
## A value object rather than a live binding: the menu is spawned on open and
## freed on close, so a row never outlives the snapshot it was built from. Badge
## counts are the one thing that can move while the menu is up, and those are
## pushed into the built rows rather than re-read from here.

var screen_type: ScreenTypes.Types
var label: String
var subtitle: String
var accent: Color
var icon_shader: Shader
var is_current: bool
var subs: Array[NavSubDestination] = []
