extends HBoxContainer
## VIEW: one line of the statistics overlay - an icon, a label on the left, a
## value on the right, or a section heading with no value at all.
##
## Two looks rather than two scenes: the records table, a run's fields and a
## bonus card's upgrades are the same label/value pair and differ only in weight.
## A scene each would be three copies of two Labels in an HBoxContainer.

## The bonus tab's upgrade rows sit two levels in - inside a track group, inside
## a card whose title is 14 - so they step down from the 13 the scene authors.
##
## The scene has to author a size at all for the same reason: with no override a
## Label takes the theme's 16, and a levelled upgrade printed larger than the
## resource it belongs to, which is exactly backwards.
const COMPACT_FONT_SIZE := 12

@export var icon: ColorRect
@export var lbl_label: Label
@export var lbl_value: Label

func set_row(label: String, value: String) -> void:
	lbl_label.text = label
	lbl_value.text = value
	lbl_value.visible = not value.is_empty()

func set_compact() -> void:
	lbl_label.add_theme_font_size_override(&"font_size", COMPACT_FONT_SIZE)
	lbl_value.add_theme_font_size_override(&"font_size", COMPACT_FONT_SIZE)

## `color` is for the rows that are about one place rather than about a number -
## a run's deepest biome takes that biome's own colour, the way the timeline's
## milestone tiles do.
func set_icon(id: StatIcons.Icon, color: Color = StatIcons.ROW_COLOR) -> void:
	_paint_icon(id, color)

## Blanked rather than hidden, and blanked through the shader rather than through
## modulate.
##
## Hidden would collapse the rect out of the HBoxContainer, and the effect lines
## under an upgrade have to keep the indent of the rows they explain. Modulate
## would do nothing at all: these icon shaders write COLOR outright instead of
## multiplying the incoming vertex colour, so the only alpha that reaches the
## screen is the one in icon_color.
func clear_icon() -> void:
	_paint_icon(StatIcons.Icon.NUTRIENTS, Color(StatIcons.ROW_COLOR, 0.0))

func _paint_icon(id: StatIcons.Icon, color: Color) -> void:
	var shader_material := icon.material as ShaderMaterial
	if not shader_material:
		return
	shader_material.set_shader_parameter(&"icon_id", int(id))
	shader_material.set_shader_parameter(&"icon_color", color)
