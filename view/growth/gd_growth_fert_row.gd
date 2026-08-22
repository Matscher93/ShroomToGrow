extends PanelContainer
## VIEW: one fertilizer upgrade's row in the growth sheet.
##
## Bound from a FertilizerRow value object rather than a live ViewModel, the same
## way the LP row above it is: the sheet is spawned on open and freed on close, so
## the panel re-binds a fresh snapshot on every refresh instead of each row
## holding a subscription of its own.

## The panel owns no state, so the press is passed up rather than acted on here.
signal buy_requested(id: StringName)

@export var lbl_label: Label
@export var lbl_level: Label
@export var lbl_description: Label
@export var btn_buy: Button

var _id: StringName

func _ready() -> void:
	btn_buy.pressed.connect(_on_buy_pressed)

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
