extends PanelContainer
## VIEW: one card in the statistics overlay - a title, something small beside it,
## an optional caption, and any number of rows underneath.
##
## Shared by the three list tabs because they are the same card: a milestone is a
## title and a date, a run is a title and a date with its fields under it, and a
## resource in the bonus breakdown is a title and a multiplier with its upgrades
## under it. Only what goes in `rows` differs, and the caller fills that.

@export var lbl_title: Label
@export var lbl_meta: Label
@export var lbl_caption: Label
@export var rows: VBoxContainer

func set_card(title: String, meta: String, caption: String) -> void:
	lbl_title.text = title
	lbl_meta.text = meta
	lbl_meta.visible = not meta.is_empty()
	lbl_caption.text = caption
	lbl_caption.visible = not caption.is_empty()
