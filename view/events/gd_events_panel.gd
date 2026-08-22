extends PanelContainer
## VIEW: the events sheet - every offer currently on the board - shown as a
## full-screen overlay over whatever screen the player is on. Reached from the
## bell in the top bar.
##
## An overlay rather than a screen for the same reason the achievement archive and
## the growth sheet are: an offer arrives while the player is off doing something
## else, and walking to another screen to answer it was the friction worth
## removing. It shares their layer too - all three are answers to "what is waiting
## for me", so opening one replaces the other rather than stacking on it.
##
## The root is the dimmed backdrop; tapping it closes, exactly like the close
## button. The sheet inside it is a PanelContainer, so it swallows its own presses
## and a tap on a card never reaches the backdrop.

## Emitted when the player dismisses the overlay. Whoever spawned this instance
## owns freeing it. This view never queue_frees itself, so it can't desync the
## PopupLayer's tracked ref.
signal dismissed

@export var btn_close: Button
@export var lbl_count: Label
@export var vbox_events: VBoxContainer
@export var panel_empty: PanelContainer
@export var event_card_scene: PackedScene

var _vm: EventsViewModel

func _ready() -> void:
	btn_close.pressed.connect(_on_dismiss_pressed)
	bind(App.events_vm)

func bind(vm: EventsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(_property: StringName) -> void:
	_refresh()

## Unlike the growth sheet's fixed producer list, the queue changes length as
## events spawn and are answered, so the cards are rebuilt rather than re-bound.
## Collecting one is what most often triggers this, and that card is on its way
## out anyway - there is no press to tear out from under a finger.
func _refresh() -> void:
	var rows := _vm.rows
	lbl_count.text = "%d / %d" % [rows.size(), EventSystem.MAX_QUEUE]
	panel_empty.visible = rows.is_empty()
	for child in vbox_events.get_children():
		vbox_events.remove_child(child)
		child.queue_free()
	for row in rows:
		var card := event_card_scene.instantiate()
		vbox_events.add_child(card)
		card.bind(row)
		card.collect_requested.connect(_on_collect_requested)
		card.fulfil_requested.connect(_on_fulfil_requested)
		card.skip_requested.connect(_on_skip_requested)

func _on_collect_requested(instance_id: int) -> void:
	_vm.collect(instance_id)

func _on_fulfil_requested(instance_id: int) -> void:
	_vm.fulfil(instance_id)

func _on_skip_requested(instance_id: int) -> void:
	_vm.skip(instance_id)

## Presses that reached the backdrop missed the sheet, so they are a tap outside
## the overlay.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_dismiss_pressed()

func _on_dismiss_pressed() -> void:
	dismissed.emit()
