extends PanelContainer
## VIEW: one entry in the point plan the SPEND_BIOME_POINTS automation follows.
## Reorder and target buttons report back to CrystalCavesPanel, which owns the
## list and rebuilds it; this row holds no state of its own beyond its index.

signal move_up_pressed(index: int)
signal move_down_pressed(index: int)
signal target_pressed(index: int)

@export var lbl_name: Label
@export var lbl_level: Label
@export var btn_target: Button
@export var btn_up: Button
@export var btn_down: Button

var _index: int = 0

func _ready() -> void:
	btn_up.pressed.connect(func() -> void: move_up_pressed.emit(_index))
	btn_down.pressed.connect(func() -> void: move_down_pressed.emit(_index))
	btn_target.pressed.connect(func() -> void: target_pressed.emit(_index))

## `row` is one entry of CrystalCavesViewModel.plan_rows(): the only shape this
## view knows about.
func set_row(index: int, row: Dictionary, is_first: bool, is_last: bool) -> void:
	_index = index
	lbl_name.text = row["name"]
	lbl_level.text = row["level_text"]
	btn_target.text = row["target_text"]
	btn_up.disabled = is_first
	btn_down.disabled = is_last
