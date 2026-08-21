extends MarginContainer
## VIEW: the indented group holding one destination's sub-view rows, with a rail
## down the left tinted to that destination's accent.

@export var rail: PanelContainer
@export var vbox: VBoxContainer

func set_accent(accent: Color) -> void:
	var style := rail.get_theme_stylebox(&"panel") as StyleBoxFlat
	style.bg_color = Color(accent, 0.22)

func add_row(row: Control) -> void:
	vbox.add_child(row)
