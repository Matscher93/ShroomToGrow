extends HBoxContainer
## VIEW: one line of the statistics overlay - a label on the left, a value on the
## right, or a section heading with no value at all.
##
## Three looks rather than three scenes: every list in the overlay is the same
## label/value pair, and the records table, a run's fields, a track heading and an
## upgrade's effect lines differ only in weight. A scene each would be four copies
## of two Labels in an HBoxContainer.

## Section headings are dimmer and quieter than the rows under them, matching the
## caption colour the rest of the game's sheets use.
const HEADER_COLOR := Color(0.43529412, 0.52156866, 0.47843137, 1)

@export var lbl_label: Label
@export var lbl_value: Label

func set_row(label: String, value: String) -> void:
	lbl_label.text = label
	lbl_value.text = value
	lbl_value.visible = not value.is_empty()

## Dimmed, for the lines that explain a row above them rather than being one -
## an upgrade's individual effects, a milestone's caption.
func set_muted(muted: bool) -> void:
	modulate = Color(1, 1, 1, 0.65) if muted else Color(1, 1, 1, 1)

## An all-caps heading with no value beside it, for the track groupings inside a
## bonus breakdown.
func set_header(text: String) -> void:
	set_row(text.to_upper(), "")
	lbl_label.add_theme_font_size_override(&"font_size", 11)
	lbl_label.add_theme_color_override(&"font_color", HEADER_COLOR)
