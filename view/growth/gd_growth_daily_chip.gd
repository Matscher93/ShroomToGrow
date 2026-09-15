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

## How far a claimed chip's icon is pulled towards black, matching the 0.55
## modulate the rest of the chip is dimmed by.
const DIMMED_ICON_AMOUNT := 0.45

@export var icon: ColorRect
@export var lbl_label: Label
@export var lbl_stacks: Label
@export var btn_claim: Button

var _currency: CurrencyTypes.Types

func _ready() -> void:
	btn_claim.pressed.connect(_on_claim_pressed)

func bind(row: GrowthRow) -> void:
	_currency = row.currency
	_paint_icon(row.currency, row.accent, row.enabled)
	lbl_label.text = row.label
	lbl_stacks.text = row.value_text
	btn_claim.disabled = not row.enabled
	# Claimed chips stay on screen showing what they have banked, so the grid is
	# also the record of where past rewards went. Dimmed rather than removed.
	modulate = Color(1.0, 1.0, 1.0, 1.0 if row.enabled else 0.55)
	lbl_label.add_theme_color_override(&"font_color", row.text_color)

## The chip draws the same currency shape the top bar's pill does, off the same
## shader - CurrencyTypes documents that ordinal as its icon_id. The material is
## resource_local_to_scene, so writing icon_id here moves this chip only.
##
## A claimed chip is dimmed in the icon's own colour rather than left to the
## modulate above: this shader writes COLOR outright instead of multiplying the
## incoming vertex colour, so a parent modulate never reaches it. Darkened rather
## than faded for the same reason - circle_color's alpha is dropped too, the
## shape's coverage being the only alpha that gets written.
func _paint_icon(currency: CurrencyTypes.Types, color: Color, in_enabled: bool) -> void:
	var shader_material := icon.material as ShaderMaterial
	if not shader_material:
		return
	shader_material.set_shader_parameter(&"icon_id", int(currency))
	shader_material.set_shader_parameter(&"circle_color",
		color if in_enabled else color.darkened(DIMMED_ICON_AMOUNT))

func _on_claim_pressed() -> void:
	claim_requested.emit(_currency)
