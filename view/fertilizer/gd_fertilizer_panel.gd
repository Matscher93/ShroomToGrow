extends PanelContainer
## VIEW: the fertilizer sheet - the stock random events have paid out and the
## upgrades it buys - shown as a full-screen overlay over whatever screen the
## player is on.
##
## An overlay rather than a screen for the same reason the growth sheet is one:
## fertilizer piles up while the player is off doing something else, and walking
## to another screen to spend it was the friction worth removing. It is reached
## from the fertilizer chip in the top bar.
##
## The root is the dimmed backdrop; tapping it closes, exactly like the close
## button. The sheet inside it is a PanelContainer, so it swallows its own
## presses and a tap on a row never reaches the backdrop.

## Emitted when the player dismisses the overlay. Whoever spawned this instance
## owns freeing it. This view never queue_frees itself, so it can't desync the
## PopupLayer's tracked ref.
signal dismissed

@export var btn_close: Button
@export var lbl_balance: Label
@export var vbox_rows: VBoxContainer
@export var row_scene: PackedScene

var _vm: FertilizerViewModel

func _ready() -> void:
	btn_close.pressed.connect(_on_dismiss_pressed)
	bind(App.fertilizer_vm)
	_build_rows()

func bind(vm: FertilizerViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

## The sheet has one source, so there is nothing to match on: a purchase moves
## the rows and the stock caption together, and a payout moves both the other
## way.
func _on_property_changed(_property: StringName) -> void:
	_refresh()

## Rows are instantiated once and re-bound afterwards. The upgrade list is fixed
## at load, and rebuilding the nodes on every notification would tear the row out
## from under a finger mid-press.
func _build_rows() -> void:
	# Painted from the CurrencyDef rather than from the green each of these
	# scenes used to hardcode. Fertilizer got a def of its own precisely because
	# it was the one currency whose colour lived in whichever scene happened to
	# draw it - the values still in sc_fertilizer_panel.tscn and
	# sc_fertilizer_upgrade_row.tscn are the editor's preview, overwritten here.
	var accent := _fertilizer_color()
	lbl_balance.label_settings.font_color = accent
	for _i in _vm.rows.size():
		var row := row_scene.instantiate()
		vbox_rows.add_child(row)
		row.set_accent(accent)
		row.buy_requested.connect(_on_buy_requested)
	_refresh_rows()

## Static registry read of a field fixed for the def's lifetime, which is the
## case the ViewModel rule carves out. Falls back to what the scenes already
## carry, so a missing def leaves the sheet looking as it always has rather than
## painting it black.
func _fertilizer_color() -> Color:
	var def: CurrencyDef = App.currencies.currencies.get(CurrencyTypes.Types.FERTILIZER)
	return def.main_color if def else lbl_balance.label_settings.font_color

func _refresh() -> void:
	lbl_balance.text = _vm.balance_text
	_refresh_rows()

func _refresh_rows() -> void:
	var rows := _vm.rows
	for i in range(mini(rows.size(), vbox_rows.get_child_count())):
		vbox_rows.get_child(i).bind(rows[i])

func _on_buy_requested(id: StringName) -> void:
	_vm.buy(id)

## Presses that reached the backdrop missed the sheet, so they are a tap outside
## the overlay.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_dismiss_pressed()

func _on_dismiss_pressed() -> void:
	dismissed.emit()
