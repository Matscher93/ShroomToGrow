extends PanelContainer
## VIEW: one day of the daily-reward track in the growth sheet.
##
## Bound from a DailyTrackRow value object, like the LP rows and daily chips
## beside it. Today's slot is the press that takes the step; every other slot is
## a record, so its button is disabled rather than absent - a grid where only one
## tile is a button and the rest are panels changes height as the track advances.
##
## The whole slot is the button, wrapped the way the daily chip wraps its own: a
## flat Button as the panel's second child, filling it over the labels the first
## child lays out.

## How far a day that is behind or ahead of the player is pulled towards black.
## Claimed days stay legible - they are the record of the run so far - while
## locked ones recede to the shape and the number alone.
const CLAIMED_DIM := 0.35
const LOCKED_DIM := 0.62

## The day heading on every slot but today's, matching the scene's authored
## LabelSettings - which the override below has to be able to put back.
const DAY_COLOR := Color(0.43529412, 0.52156866, 0.47843137, 1.0)

## The panel owns no state, so the press is passed up rather than acted on here.
signal claim_requested

@export var icon: ColorRect
@export var lbl_day: Label
@export var lbl_amount: Label
@export var btn_claim: Button

func _ready() -> void:
	btn_claim.pressed.connect(_on_claim_pressed)

func bind(row: DailyTrackRow) -> void:
	btn_claim.disabled = row.state != DailyTrackRow.State.TODAY
	lbl_day.text = "D%d" % row.day
	lbl_amount.text = row.amount_text
	var shader_material := icon.material as ShaderMaterial
	if shader_material:
		# Re-read on every bind rather than set once at build: which resource a day
		# pays moves the moment a biome unlocks, and the sheet stays open across one.
		shader_material.set_shader_parameter(&"icon_id", int(row.currency))
	var accent := row.accent
	match row.state:
		DailyTrackRow.State.TODAY:
			# The only pressable tile in the grid: its heading takes the currency's
			# colour too, so the tile the hint tells the player to tap is the one
			# that looks unlike the thirteen records around it.
			_paint(accent, Color(accent, 0.16), Color(accent, 0.6), accent, accent)
		DailyTrackRow.State.CLAIMED:
			var claimed := accent.darkened(CLAIMED_DIM)
			_paint(claimed, Color(accent, 0.06), Color(accent, 0.26), claimed, DAY_COLOR)
		_:
			var locked := accent.darkened(LOCKED_DIM)
			_paint(locked, Color(1.0, 1.0, 1.0, 0.03), Color(1.0, 1.0, 1.0, 0.06),
				Color(0.45, 0.53, 0.49), DAY_COLOR)

## The panel's own style rather than one of three authored boxes: the border and
## the fill are the currency's colour, so the three states are one box with
## different alphas rather than three boxes that would each need a copy per
## currency. The .tscn marks it resource_local_to_scene, so a slot's writes stay
## on that slot.
func _paint(icon_color: Color, bg: Color, border: Color, amount_color: Color,
		day_color: Color) -> void:
	var shader_material := icon.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter(&"circle_color", icon_color)
	var style := get_theme_stylebox(&"panel") as StyleBoxFlat
	if style:
		style.bg_color = bg
		style.border_color = border
	lbl_amount.add_theme_color_override(&"font_color", amount_color)
	lbl_day.add_theme_color_override(&"font_color", day_color)

func _on_claim_pressed() -> void:
	claim_requested.emit()
