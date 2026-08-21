extends PanelContainer
## VIEW: one producer's Level Point row in the growth sheet.
##
## Bound from a GrowthRow value object rather than a live ViewModel, the same way
## a nav row is: the sheet is spawned on open and freed on close, so the panel
## re-binds a fresh snapshot on every refresh instead of each row holding a
## subscription of its own.

## The panel owns no state, so the press is passed up rather than acted on here.
signal invest_requested(currency: CurrencyTypes.Types)

@export var color_dot: ColorRect
@export var lbl_label: Label
@export var lbl_detail: Label
@export var btn_invest: Button

var _currency: CurrencyTypes.Types

func _ready() -> void:
	btn_invest.pressed.connect(_on_invest_pressed)

func bind(row: GrowthRow) -> void:
	_currency = row.currency
	color_dot.color = row.accent
	lbl_label.text = row.label
	lbl_label.add_theme_color_override(&"font_color", row.text_color)
	lbl_detail.text = "%s output - %s" % [row.value_text, row.detail_text]
	# Kept visible but disabled rather than hidden, so the sheet doesn't change
	# height the moment the last point is spent.
	btn_invest.disabled = not row.enabled

func _on_invest_pressed() -> void:
	invest_requested.emit(_currency)
