extends PanelContainer
## VIEW: one step of a biome's recorded upgrade sequence. Reorder and remove
## report back to the section, which owns the list and rebuilds it; this row
## holds no state of its own beyond its index.

signal move_up_pressed(index: int)
signal move_down_pressed(index: int)
signal remove_pressed(index: int)

## Warm amber for a step the replay would have to skip, distinct from the plain
## dimming that only means "already bought".
const UNREACHABLE_COLOR := Color(1.0, 0.72, 0.35, 1.0)

@export var lbl_step: Label
@export var lbl_name: Label
@export var btn_up: Button
@export var btn_down: Button
@export var btn_remove: Button

var _index: int = 0

func _ready() -> void:
	btn_up.pressed.connect(func() -> void: move_up_pressed.emit(_index))
	btn_down.pressed.connect(func() -> void: move_down_pressed.emit(_index))
	btn_remove.pressed.connect(func() -> void: remove_pressed.emit(_index))

## `row` is one entry of BiomeSequenceViewModel.sequence_rows(): the only shape
## this view knows about.
func set_row(row: Dictionary, is_first: bool, is_last: bool) -> void:
	_index = row["index"]
	lbl_name.text = row["name"]
	# Steps the biome has already bought are dimmed rather than hidden: the
	# sequence is a build order, and seeing how far through it the replay has
	# got is the point of showing it at all.
	modulate.a = 0.45 if row["done"] else 1.0
	# A step sitting earlier than its own point gate can never be bought when its
	# turn comes. New steps can't be added in that state, but removing or moving
	# one can push a later step above its gate, and the replay would then skip it
	# silently.
	var reachable: bool = row["reachable"]
	lbl_step.text = "%d." % [_index + 1] if reachable else "!"
	lbl_name.modulate = Color.WHITE if reachable else UNREACHABLE_COLOR
	tooltip_text = "" if reachable else "Too early - not enough points spent by this step"
	btn_up.disabled = is_first
	btn_down.disabled = is_last
