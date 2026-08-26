extends PanelContainer
## VIEW: the growth sheet - the account level, the Level Points it has banked, the
## fertilizer events have paid out and today's daily reward - shown as a
## full-screen overlay over whatever screen the player is on.
##
## An overlay rather than a screen for the same reason the achievement archive is
## one: points and rewards pile up while the player is off doing something else,
## and walking to another screen to spend them was the friction worth removing.
## It is reached from the level chip in the top bar.
##
## The root is the dimmed backdrop; tapping it closes, exactly like the close
## button. The sheet inside it is a PanelContainer, so it swallows its own
## presses and a tap on a row never reaches the backdrop.

## Emitted when the player dismisses the overlay. Whoever spawned this instance
## owns freeing it. This view never queue_frees itself, so it can't desync the
## PopupLayer's tracked ref.
signal dismissed

@export var btn_close: Button
@export var lbl_level: Label
@export var lbl_lp_free: Label
@export var bar_level: ProgressBar
@export var lbl_level_progress: Label
@export var lbl_double_now: Label
@export var bar_double: ProgressBar
@export var lbl_double_hint: Label
@export var vbox_lp_rows: VBoxContainer
@export var lbl_fert_balance: Label
@export var vbox_fert_rows: VBoxContainer
@export var lbl_daily_streak: Label
@export var lbl_daily_hint: Label
@export var grid_daily: GridContainer
@export var lp_row_scene: PackedScene
@export var fert_row_scene: PackedScene
@export var daily_chip_scene: PackedScene

var _vm: GrowthViewModel

func _ready() -> void:
	btn_close.pressed.connect(_on_dismiss_pressed)
	bind(App.growth_vm)
	_build_rows()

func bind(vm: GrowthViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

## Every notification refreshes the whole sheet rather than matching on which one
## arrived. The sources are not independent: claiming a daily buys a level in the
## same track an investment does, so a claim moves the rows *and* the day state,
## and a level-up moves the header *and* every row's enabled flag. Splitting that
## up buys nothing - the refresh is a handful of label writes - and every way of
## splitting it has a dependency to miss.
func _on_property_changed(_property: StringName) -> void:
	_refresh()

## Rows are instantiated once and re-bound afterwards. The producer list is fixed
## at load, and rebuilding the nodes on every notification would tear the row out
## from under a finger mid-press - the level notification alone arrives once a
## tick.
func _build_rows() -> void:
	for _i in _vm.lp_rows.size():
		var row := lp_row_scene.instantiate()
		vbox_lp_rows.add_child(row)
		row.invest_requested.connect(_on_invest_requested)
	# Painted from the CurrencyDef rather than from the green each of these
	# scenes used to hardcode. Fertilizer got a def of its own precisely because
	# it was the one currency whose colour lived in whichever scene happened to
	# draw it - the values still in sc_growth_panel.tscn and
	# sc_growth_fert_row.tscn are the editor's preview, overwritten here.
	var accent := _fertilizer_color()
	lbl_fert_balance.label_settings.font_color = accent
	for _i in _vm.fert_rows.size():
		var fert_row := fert_row_scene.instantiate()
		vbox_fert_rows.add_child(fert_row)
		fert_row.set_accent(accent)
		fert_row.buy_requested.connect(_on_fert_buy_requested)
	for _i in _vm.daily_rows.size():
		var chip := daily_chip_scene.instantiate()
		grid_daily.add_child(chip)
		chip.claim_requested.connect(_on_claim_requested)
	_refresh_rows()

## Static registry read of a field fixed for the def's lifetime, which is the
## case the ViewModel rule carves out. Falls back to what the scenes already
## carry, so a missing def leaves the sheet looking as it always has rather than
## painting it black.
func _fertilizer_color() -> Color:
	var def: CurrencyDef = App.currencies.currencies.get(CurrencyTypes.Types.FERTILIZER)
	return def.main_color if def else lbl_fert_balance.label_settings.font_color

func _refresh() -> void:
	lbl_level.text = _vm.level_text
	lbl_lp_free.text = _vm.lp_available_text
	bar_level.value = _vm.level_pct * 100.0
	lbl_level_progress.text = _vm.level_progress_text
	lbl_double_now.text = "%s now" % _vm.global_double_text
	bar_double.value = _vm.global_pct_fill * 100.0
	lbl_double_hint.text = _vm.next_double_hint_text
	lbl_fert_balance.text = _vm.fert_balance_text
	lbl_daily_streak.text = _vm.daily_streak_text
	lbl_daily_hint.text = _vm.daily_hint_text
	_refresh_rows()

func _refresh_rows() -> void:
	var lp_rows := _vm.lp_rows
	for i in range(mini(lp_rows.size(), vbox_lp_rows.get_child_count())):
		vbox_lp_rows.get_child(i).bind(lp_rows[i])
	var fert_rows := _vm.fert_rows
	for i in range(mini(fert_rows.size(), vbox_fert_rows.get_child_count())):
		vbox_fert_rows.get_child(i).bind(fert_rows[i])
	var daily_rows := _vm.daily_rows
	for i in range(mini(daily_rows.size(), grid_daily.get_child_count())):
		grid_daily.get_child(i).bind(daily_rows[i])

func _on_invest_requested(currency: CurrencyTypes.Types) -> void:
	_vm.invest(currency)

func _on_claim_requested(currency: CurrencyTypes.Types) -> void:
	_vm.claim_daily(currency)

func _on_fert_buy_requested(id: StringName) -> void:
	_vm.buy_fertilizer(id)

## Presses that reached the backdrop missed the sheet, so they are a tap outside
## the overlay.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_dismiss_pressed()

func _on_dismiss_pressed() -> void:
	dismissed.emit()
