extends PanelContainer
## VIEW: one step of a biome's recorded upgrade sequence. Display only - the
## sequence is append-only and truncated from the end, so a row has nothing to
## act on and holds no state beyond what it was last handed.

@export var lbl_step: Label
@export var lbl_name: Label

## `row` is one entry of BiomeSequenceViewModel.sequence_rows(): the only shape
## this view knows about.
func set_row(row: Dictionary) -> void:
	lbl_step.text = "%d." % [int(row["index"]) + 1]
	lbl_name.text = row["name"]
	# Steps the biome has already bought are dimmed rather than hidden: the
	# sequence is a build order, and seeing how far through it the replay has
	# got is the point of showing it at all.
	modulate.a = 0.45 if row["done"] else 1.0
