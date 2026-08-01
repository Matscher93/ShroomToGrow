class_name PopupLayer
extends MarginContainer
## VIEW: generic host for transient popups. At most one lives here at a time,
## showing a new one clears whatever is up.

var _current: Node = null

func show_popup(scene: PackedScene) -> Node:
	clear()
	var instance := scene.instantiate()
	add_child(instance)
	_current = instance
	return instance

func clear() -> void:
	if _current:
		_current.queue_free()
		_current = null
