extends PanelContainer
## VIEW: the nav menu, shown as an overlay anchored above the menu disc. Replaces
## the bottom button bar: one row per destination the player has reached, with
## each screen's sub-views as indented rows under it.
##
## The root is the dimmed backdrop; tapping it closes, exactly like tapping a
## row. The card inside it is a PanelContainer, so it swallows its own presses
## and a tap on a row never reaches the backdrop. Same shape as the achievements
## overlay - see view/achievements/.

## Emitted when the player dismisses the menu. Whoever spawned this instance owns
## freeing it. This view never queue_frees itself, so it can't desync the
## PopupLayer's tracked ref.
signal dismissed

const ROW_SCENE := preload("res://view/navigation/sc_nav_row.tscn")
const SUB_ROW_SCENE := preload("res://view/navigation/sc_nav_sub_row.tscn")
const SUB_ROW_CONTAINER_SCENE := preload("res://view/navigation/sc_nav_sub_row_container.tscn")

const OPEN_DURATION := 0.18
## The card starts visible rather than at nothing, so a slow frame never shows a
## dimmed screen with no menu on it.
const START_ALPHA := 0.35
## Scaled out of the disc's corner rather than translated: the card is laid out
## by a container, and a position tween on a container child is overwritten the
## next time that container sorts. The pivot does the same job without fighting.
const START_SCALE := 0.94
## Leaves the active row clear of the card's top edge when the list scrolls to
## it, rather than flush against the rounded corner.
const SCROLL_MARGIN := 11


@export var card: PanelContainer
@export var scroll: ScrollContainer
@export var vbox_rows: VBoxContainer

var _vm: NavigationViewModel
## Sub rows paired with the count they show, so a currency change can repaint the
## numbers without rebuilding the list under the player's finger. Top-level rows
## carry no badge, so none of them are in here.
var _badge_rows: Array[Dictionary] = []
var _active_row: Control = null

func _ready() -> void:
	# Both of these keep the menu correct without ever holding it hidden: the
	# slot's height (what caps the card) and the card's own height (what the
	# entrance scales from) only exist after a layout pass, so react to that
	# layout instead of waiting frames for it.
	card.get_parent().resized.connect(_resize_card)
	card.resized.connect(_update_pivot)
	bind(App.navigation_vm)
	_animate_open()

func bind(vm: NavigationViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_build_rows()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

## The rebuild is deferred, and has to be.
##
## Tapping a row calls go_to(), which reaches ScreensData.select(), which emits
## screen_changed synchronously - and that lands back here as
## PROP_DESTINATIONS_CHANGED while the row's own `selected` emission is still on
## the stack. Rebuilding in place would free that row out from under the handler
## that is still running in it. Dismissing first is not enough on its own:
## PopupLayer.clear() queue_free()s the menu, which is deferred, so this stays
## connected for the rest of the frame.
func _on_property_changed(property: StringName) -> void:
	match property:
		NavigationViewModel.PROP_DESTINATIONS_CHANGED:
			_build_rows.call_deferred()
		NavigationViewModel.PROP_BADGES_CHANGED:
			_refresh_badges()

# --- Building ---

func _build_rows() -> void:
	for child in vbox_rows.get_children():
		vbox_rows.remove_child(child)
		child.queue_free()
	_badge_rows.clear()
	_active_row = null

	for destination in _vm.destinations:
		var row := ROW_SCENE.instantiate()
		vbox_rows.add_child(row)
		row.bind(destination)
		row.selected.connect(_on_destination_selected)
		if destination.is_current:
			_active_row = row
		if not destination.subs.is_empty():
			_build_sub_rows(destination)

	# A biome unlocked while the menu is up adds a row, so the cap is re-taken
	# here rather than only on open.
	_resize_card()

## Sub rows sit in their own indented group with a rail down the left, tinted to
## the parent's accent: at this indent the rail is what says the rows belong to
## the destination above them rather than being three more destinations.
func _build_sub_rows(destination: NavDestination) -> void:
	var container := SUB_ROW_CONTAINER_SCENE.instantiate()
	vbox_rows.add_child(container)
	container.set_accent(destination.accent)
	for sub in destination.subs:
		var sub_row := SUB_ROW_SCENE.instantiate()
		container.add_row(sub_row)
		sub_row.bind(sub)
		sub_row.selected.connect(_on_sub_selected)
		_badge_rows.append({"node": sub_row, "source": sub.badge_source})

## Counts move while the menu is open - a claim can make a boost affordable - and
## rebuilding the list to show that would shift the rows under a finger already
## on its way down. Only the numbers change.
func _refresh_badges() -> void:
	for entry in _badge_rows:
		entry["node"].set_badge(_vm.badge_count(entry["source"]))

# --- Opening ---

## Grows out of the disc's corner rather than fading in place, so the menu reads
## as belonging to the button that opened it.
##
## Nothing here waits on a frame, and that is the whole point. The backdrop
## already swallows input the moment this node enters the tree, so any part of
## the entrance that is measured in *frames* rather than seconds is a window
## where the menu is invisible but still eating taps - and the second tap lands
## on the backdrop and closes the menu the player was waiting to see. On a save
## heavy enough to drop the frame rate that window is long enough to hit every
## time, which read as "the menu opens empty".
##
## So the backdrop is up at full strength immediately and only the card animates,
## from a visible 0.35 rather than from nothing.
func _animate_open() -> void:
	_update_pivot()
	card.scale = Vector2(START_SCALE, START_SCALE)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, OPEN_DURATION).from(START_ALPHA)
	tween.tween_property(card, "scale", Vector2.ONE, OPEN_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_scroll_to_active_when_laid_out()

## The card scales out of its own bottom-left corner, which is where the disc is.
func _update_pivot() -> void:
	card.pivot_offset = Vector2(0, card.size.y)

## The card hugs its rows until it runs out of room, then stops growing and lets
## the list scroll inside it. Driven off the ScrollContainer's minimum size
## because that is what the card is sized by - a ScrollContainer asks for nothing
## on its own, so without this the card would collapse to its margins.
func _resize_card() -> void:
	var style := card.get_theme_stylebox(&"panel")
	var chrome := style.content_margin_top + style.content_margin_bottom
	# The slot's own margins are what hold the card clear of the disc below and
	# the resource bar above, so the room the card has is what is left inside
	# them - not the slot's outer height.
	var slot := card.get_parent() as MarginContainer
	var insets := slot.get_theme_constant(&"margin_top") + slot.get_theme_constant(&"margin_bottom")
	# Before the first layout the slot has no height yet. The viewport is the box
	# it will fill, and it is known immediately, so the card is sized right on the
	# frame it appears instead of spending one collapsed to its margins.
	var slot_height := slot.size.y if slot.size.y > 0.0 else get_viewport_rect().size.y
	var available := maxf(slot_height - insets - chrome, 0.0)
	var wanted := minf(vbox_rows.get_combined_minimum_size().y, available)
	if not is_equal_approx(scroll.custom_minimum_size.y, wanted):
		scroll.custom_minimum_size.y = wanted

## The one thing that genuinely cannot be done before a layout: rows have no
## position until they have been laid out. Scroll offset does not affect whether
## the menu is visible, so this is the only part left waiting on a frame.
func _scroll_to_active_when_laid_out() -> void:
	await get_tree().process_frame
	# The player can close the menu inside that frame, which frees this node.
	if not is_inside_tree():
		return
	_scroll_to_active()

## Opens on the row the player is standing on, so a long list does not hide where
## they already are.
func _scroll_to_active() -> void:
	if _active_row == null:
		return
	if scroll.get_v_scroll_bar().max_value <= scroll.size.y:
		return
	scroll.scroll_vertical = maxi(0, int(_active_row.position.y) - SCROLL_MARGIN)

# --- Input ---

## Presses that reached the backdrop missed the card, so they are a tap outside
## the menu.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		dismissed.emit()

## Dismissed before navigating, so the menu is already on its way out by the time
## screen_changed comes back around. The re-entrancy this used to cause is handled
## in _on_property_changed(), which is where the actual fix lives - queue_free()
## is deferred, so this ordering alone would not be enough.
func _on_destination_selected(screen_type: ScreenTypes.Types) -> void:
	dismissed.emit()
	_vm.go_to(screen_type)

func _on_sub_selected(screen_type: ScreenTypes.Types, tab_index: int) -> void:
	dismissed.emit()
	_vm.go_to(screen_type, tab_index)
