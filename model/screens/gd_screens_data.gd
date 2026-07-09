class_name ScreensData
extends RefCounted

signal screen_changed(screen_type: ScreenTypes.Types)

var screen_data : Dictionary[ScreenTypes.Types, ScreenDefinition]
var current_screen : ScreenTypes.Types:
	set(value):
		if value != current_screen:
			current_screen = value
			screen_changed.emit(current_screen)
			
func _init(screens : Dictionary, initial_screen: ScreenTypes.Types) -> void:
	screen_data = screens
	current_screen = initial_screen
