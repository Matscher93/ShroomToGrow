extends PanelContainer
## VIEW: one producer's daily-reward chip in the growth sheet.
##
## The whole chip is the button - there is one decision on it and nothing else to
## press - so a flat Button sits as the panel's second child and fills it, over
## the labels the first child lays out. That is the same wrapping
## gd_base_shader_button.gd does, minus the shader this row has no use for.
##
## Bound from a GrowthRow value object, like the LP rows beside it.

signal claim_requested(currency: CurrencyTypes.Types)

@export var color_dot: ColorRect
@export var lbl_label: Label
@export var lbl_stacks: Label
@export var btn_claim: Button

var _currency: CurrencyTypes.Types

func _ready() -> void:
	btn_claim.pressed.connect(_on_claim_pressed)

func bind(row: GrowthRow) -> void:
	_currency = row.currency
	color_dot.color = row.accent
	lbl_label.text = row.label
	lbl_stacks.text = row.value_text
	btn_claim.disabled = not row.enabled
	# Claimed chips stay on screen showing what they have banked, so the grid is
	# also the record of where past rewards went. Dimmed rather than removed.
	modulate = Color(1.0, 1.0, 1.0, 1.0 if row.enabled else 0.55)
	lbl_label.add_theme_color_override(&"font_color", row.text_color)

func _on_claim_pressed() -> void:
	claim_requested.emit(_currency)
