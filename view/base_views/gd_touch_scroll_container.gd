class_name TouchScrollContainer
extends ScrollContainer
## VIEW: a ScrollContainer whose touch drag no child can swallow.
##
## Godot only drag-scrolls when the ScrollContainer itself receives the touch, so
## every MOUSE_FILTER_STOP child - which is every Button - is a dead zone where a
## drag does nothing. These lists are mostly buttons, so that is most of the
## screen, and a drag that starts on a buy button just stops the scroll.
##
## _input() runs before GUI input is dispatched, so the drag is picked up here no
## matter what the children's mouse filters are, and the scrolling is done by
## hand. Once the finger has travelled far enough to count as a scroll rather than
## a tap, the press under it is cancelled by pushing a pointer motion far outside
## every control: BaseButton only emits pressed if the pointer is still inside on
## release, and the collapsible cards cancel their own tap the same way. So a
## scroll never buys anything and never collapses a card.
##
## Only touch is intercepted; mouse wheel and scrollbars stay untouched.

## Below this the gesture is still a tap, so the buttons under it keep it.
const DRAG_START_DISTANCE := 12.0
## Momentum after the finger lifts: decay per second, and the speed to stop at.
const FLICK_DECAY := 8.0
const FLICK_MIN_SPEED := 30.0

var _touch_index := -1
var _last_y := 0.0
var _travelled := 0.0
var _dragging := false
var _flick_speed := 0.0
var _inside_popup := false

func _ready() -> void:
	set_process(false)
	_inside_popup = _has_popup_ancestor()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)

func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index != -1 or _covered_by_popup() or not get_global_rect().has_point(event.position):
			return
		_touch_index = event.index
		_last_y = event.position.y
		_travelled = 0.0
		_dragging = false
		# Touching the list catches a running flick, like every native list does.
		_flick_speed = 0.0
		set_process(false)
	elif event.index == _touch_index:
		_touch_index = -1
		if _dragging and absf(_flick_speed) >= FLICK_MIN_SPEED:
			set_process(true)
		else:
			_flick_speed = 0.0
		_dragging = false

func _on_drag(event: InputEventScreenDrag) -> void:
	if event.index != _touch_index:
		return
	var delta := event.position.y - _last_y
	_last_y = event.position.y
	_travelled += absf(delta)
	if not _dragging:
		if _travelled < DRAG_START_DISTANCE:
			return
		_dragging = true
		_cancel_pointer_press()
	scroll_vertical -= int(roundf(delta))
	_flick_speed = event.velocity.y
	# Swallow it so the built-in drag handling does not scroll a second time when
	# the finger happens to be over a part of the list that does pass events on.
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if absf(_flick_speed) < FLICK_MIN_SPEED:
		_flick_speed = 0.0
		set_process(false)
		return
	var before := scroll_vertical
	scroll_vertical -= int(roundf(_flick_speed * delta))
	if scroll_vertical == before:
		# Hit an end of the list.
		_flick_speed = 0.0
		set_process(false)
		return
	_flick_speed = lerpf(_flick_speed, 0.0, minf(FLICK_DECAY * delta, 1.0))

## An open popup covers the whole screen, so a drag over it belongs to the popup,
## never to a list behind it. Reading input before the GUI does means nothing else
## tells us that, so the popup layers are asked directly.
func _covered_by_popup() -> bool:
	return PopupLayer.any_popup_open() and not _inside_popup

func _has_popup_ancestor() -> bool:
	var node := get_parent()
	while node:
		if node is PopupLayer:
			return true
		node = node.get_parent()
	return false

## Android and iOS synthesize the pointer that pressed the button from the touch,
## so moving that pointer off everything is what un-presses it.
func _cancel_pointer_press() -> void:
	var away := InputEventMouseMotion.new()
	away.position = Vector2(-100000, -100000)
	away.global_position = away.position
	Input.parse_input_event(away)
