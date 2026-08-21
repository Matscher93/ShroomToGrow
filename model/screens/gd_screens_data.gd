class_name ScreensData
extends RefCounted

signal screen_changed(screen_type: ScreenTypes.Types)

## Emitted when a nav tap asked for a specific sub-view of a screen. Separate
## from screen_changed because the screen may already be up, in which case the
## guarded setter below emits nothing and only the sub-view has to move.
signal sub_screen_requested(screen_type: ScreenTypes.Types, sub_index: int)

var screen_data: Dictionary[ScreenTypes.Types, ScreenDefinition]
var current_screen: ScreenTypes.Types:
	set(value):
		if value != current_screen:
			current_screen = value
			screen_changed.emit(current_screen)

## One nav tap, screen and sub-view together.
##
## The sub request goes first on purpose: screen_changed spawns the screen
## synchronously, and the screen's _ready() reads the remembered sub-view off its
## own ViewModel. Emitting the other way round would hand it the stale one and
## then correct it a moment later, which is a visible flick of the wrong tab.
func select(screen_type: ScreenTypes.Types, sub_index: int = -1) -> void:
	if sub_index >= 0:
		sub_screen_requested.emit(screen_type, sub_index)
	current_screen = screen_type

func _init(screens: Dictionary, initial_screen: ScreenTypes.Types) -> void:
	screen_data = screens
	current_screen = initial_screen
