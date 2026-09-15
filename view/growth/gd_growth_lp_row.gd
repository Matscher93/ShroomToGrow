extends PanelContainer
## VIEW: one producer's Level Point row in the growth sheet.
##
## Bound from a GrowthRow value object rather than a live ViewModel, the same way
## a nav row is: the sheet is spawned on open and freed on close, so the panel
## re-binds a fresh snapshot on every refresh instead of each row holding a
## subscription of its own.

## The panel owns no state, so the press is passed up rather than acted on here.
signal invest_requested(currency: CurrencyTypes.Types)
## The second button: invest up to the next doubling rather than one point.
signal invest_step_requested(currency: CurrencyTypes.Types)

@export var icon: ColorRect
@export var lbl_label: Label
@export var lbl_detail: Label
@export var btn_invest: Button
@export var btn_invest_step: Button

var _currency: CurrencyTypes.Types

func _ready() -> void:
	btn_invest.pressed.connect(_on_invest_pressed)
	btn_invest_step.pressed.connect(_on_invest_step_pressed)

func bind(row: GrowthRow) -> void:
	_currency = row.currency
	_paint_icon(row.currency, row.accent)
	lbl_label.text = row.label
	lbl_label.add_theme_color_override(&"font_color", row.text_color)
	lbl_detail.text = "%s output - %s" % [row.value_text, row.detail_text]
	# Kept visible but disabled rather than hidden, so the sheet doesn't change
	# height the moment the last point is spent.
	btn_invest.disabled = not row.enabled
	btn_invest_step.text = row.step_text
	btn_invest_step.disabled = not row.step_enabled

## The row draws the same currency shape the top bar's pill does, off the same
## shader - CurrencyTypes documents that ordinal as its icon_id. The material is
## resource_local_to_scene, so writing icon_id here moves this row only and not
## every other instance of the scene.
func _paint_icon(currency: CurrencyTypes.Types, color: Color) -> void:
	var shader_material := icon.material as ShaderMaterial
	if not shader_material:
		return
	shader_material.set_shader_parameter(&"icon_id", int(currency))
	shader_material.set_shader_parameter(&"circle_color", color)

func _on_invest_pressed() -> void:
	invest_requested.emit(_currency)

func _on_invest_step_pressed() -> void:
	invest_step_requested.emit(_currency)
