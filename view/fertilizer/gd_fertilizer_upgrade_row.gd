extends PanelContainer
## VIEW: one fertilizer upgrade's row in the fertilizer sheet.
##
## Bound from a FertilizerRow value object rather than a live ViewModel, the same
## way the growth sheet's LP rows are: the sheet is spawned on open and freed on
## close, so the panel re-binds a fresh snapshot on every refresh instead of each
## row holding a subscription of its own.

## The panel owns no state, so the press is passed up rather than acted on here.
signal buy_requested(id: StringName)

@export var lbl_label: Label
@export var lbl_level: Label
@export var lbl_description: Label
@export var btn_buy: Button

var _id: StringName

func _ready() -> void:
	btn_buy.pressed.connect(_on_buy_pressed)

## Fertilizer's own colour, pushed in by the panel from the CurrencyDef rather
## than read here: the row is a snapshot binding with no App access of its own,
## and every row in the sheet wears the same one.
##
## The three alphas are the weights the scene authored - a wash for the row, a
## little more for the level chip, full for its text.
func set_accent(accent: Color) -> void:
	var row_style := get_theme_stylebox(&"panel") as StyleBoxFlat
	row_style.bg_color = Color(accent, 0.05)
	row_style.border_color = Color(accent, 0.16)
	var level_style := lbl_level.get_parent().get_theme_stylebox(&"panel") as StyleBoxFlat
	level_style.bg_color = Color(accent, 0.12)
	lbl_level.label_settings.font_color = accent

func bind(row: FertilizerRow) -> void:
	_id = row.id
	lbl_label.text = row.label
	lbl_level.text = row.level_text
	lbl_description.text = row.description
	btn_buy.text = row.cost_text
	# Kept visible but disabled rather than hidden, so the sheet doesn't change
	# height the moment the stock dips below the price.
	btn_buy.disabled = not row.enabled

func _on_buy_pressed() -> void:
	buy_requested.emit(_id)
