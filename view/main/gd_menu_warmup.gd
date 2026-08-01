class_name MenuWarmup
extends CanvasLayer
## VIEW: instantiates every screen (Biomes, Nodes, Prestige) once, off-screen,
## right after boot. game_screens.gd builds a screen from scratch the first time
## its tab is opened, so that first tap pays for scene loading, layout and the
## screen's first draw at once. Warming up here moves that cost to startup.
##
## The screen shown at boot is skipped: game_screens is a tree ancestor and has
## already run its own _ready(). Each screen's root fills the viewport via
## full-rect anchors, matching how game_screens hosts it, so only modulate needs
## overriding to keep it invisible. Frees itself once done.

func _ready() -> void:
	for screen_type: ScreenTypes.Types in App.screens.screens:
		if screen_type == App.screens_data.current_screen:
			continue
		var screen_data: ScreenDefinition = App.screens.screens[screen_type]
		var instance := screen_data.screen_scene.instantiate() as Control
		instance.modulate.a = 0.0
		add_child(instance)
		await get_tree().process_frame
		instance.queue_free()
	queue_free()
