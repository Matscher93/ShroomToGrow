class_name PopupLayer
extends MarginContainer
## VIEW: generic host for transient popups. At most one lives here at a time,
## showing a new one clears whatever is up.

## How many popup layers currently hold a popup, across every layer. Views that
## read raw input before it reaches the GUI - the touch scrollers - are blind to
## what covers them on screen, so they ask this instead of scrolling a list the
## player can't even see.
static var _open_popups := 0

var _current: Node = null

static func any_popup_open() -> bool:
	return _open_popups > 0

func show_popup(scene: PackedScene) -> Node:
	clear()
	var instance := scene.instantiate()
	add_child(instance)
	_current = instance
	_open_popups += 1
	return instance

func has_popup() -> bool:
	return _current != null

func clear() -> void:
	if _current:
		_current.queue_free()
		_current = null
		_open_popups -= 1

func _exit_tree() -> void:
	# Keeps the count honest if the layer itself goes away while holding a popup.
	clear()
