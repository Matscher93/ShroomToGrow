extends MarginContainer

var _last_safe := Rect2i()
var _last_win := Vector2i()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var poll := Timer.new()
	poll.wait_time = 0.25            # 4Hz is plenty for a human turning a phone
	poll.timeout.connect(_check_safe_area)
	add_child(poll)
	poll.start()
	await get_tree().process_frame  # let insets settle before the first read
	_apply_safe_area()
	_apply_ui_scale()

func _check_safe_area() -> void:
	# Re-apply only when something actually moved — catches the 180° flip,
	# which changes the rect's position but not the window size.
	if DisplayServer.get_display_safe_area() != _last_safe or DisplayServer.window_get_size() != _last_win:
		_apply_safe_area()
		_apply_ui_scale()
		
func _apply_safe_area() -> void:
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var win: Vector2i = DisplayServer.window_get_size()

		# Insets in physical screen pixels
		var l := safe.position.x
		var t := safe.position.y
		var r := win.x - safe.position.x - safe.size.x
		var b := win.y - safe.position.y - safe.size.y

		# Physical px -> UI px, using the actual stretch scale on each axis
		var vp := get_viewport().get_visible_rect().size
		var sx := vp.x / float(win.x)
		var sy := vp.y / float(win.y)

		add_theme_constant_override("margin_left",   int(l * sx))
		add_theme_constant_override("margin_top",    int(t * sy))
		add_theme_constant_override("margin_right",  int(r * sx))
		add_theme_constant_override("margin_bottom", int(b * sy))
	
func _apply_ui_scale() -> void:
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96   # fallback — some devices/desktops report garbage

	var screen_px := DisplayServer.screen_get_size()
	# shorter physical edge, in inches — the honest measure of "how big is this thing"
	var short_edge := float(min(screen_px.x, screen_px.y)) / float(dpi)

	var screen_scale := 1.0
	if short_edge < 3.0:        # small phone
		screen_scale = 1.6
	elif short_edge < 4.5:      # phone / phablet
		screen_scale = 1.4
	elif short_edge < 7.0:      # small tablet
		screen_scale = 1.15
	else:                       # large tablet / desktop
		screen_scale = 1.0

	get_window().content_scale_factor = screen_scale
