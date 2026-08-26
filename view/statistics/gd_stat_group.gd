extends VBoxContainer
## VIEW: one track's group inside a bonus card - a pressable heading with the
## track's own multiplier beside it, over the upgrade rows it holds.
##
## Not a StatRow with an arrow bolted on: that scene's contract is a label on the
## left and a value on the right, and a heading that owns the rows under it and a
## press target over them is a different thing. It mirrors StatCard's shape
## instead - `toggled` out, `set_expanded()` in, no fold state of its own, since
## it is respawned on every rebuild.

signal toggled

@export var arrow: ColorRect
@export var btn_header: Button
@export var lbl_track: Label
@export var lbl_value: Label
@export var rows: VBoxContainer

func _ready() -> void:
	btn_header.pressed.connect(_on_header_pressed)

func set_group(track: String, value: String) -> void:
	lbl_track.text = track.to_upper()
	lbl_value.text = value
	lbl_value.visible = not value.is_empty()

func set_expanded(expanded: bool) -> void:
	rows.visible = expanded
	arrow.offset_transform_rotation = PI if expanded else 0.0

func _on_header_pressed() -> void:
	toggled.emit()
