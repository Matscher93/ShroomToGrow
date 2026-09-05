class_name UpgradeSlotGrid
extends RefCounted
## VIEW helper: the numbered upgrade slot, shared by the biome card's 5x2 grid
## (view/biomes/gd_biome_panel.gd) and the Crystal Caves sequence sections
## (view/crystal_caves/gd_biome_sequence_section.gd).
##
## Both show the same thing - a biome's ten upgrades as numbered slots with their
## level underneath - and only differ in what a press does, so the look lives
## here and the behaviour stays with each caller.
##
## The level Label is stashed on the Button as metadata rather than handed back
## in a parallel array, so callers cannot get the two out of step.

const COLUMNS := 5
const SLOT_HEIGHT := 44
const INDEX_FONT_SIZE := 16
const LEVEL_FONT_SIZE := 10
const LEVEL_COLOR := Color(1, 1, 1, 0.6)
## The slot's resting fill. Named because set_affordable() rebuilds the same
## stylebox to put a border on it, and the two must not drift apart.
const NORMAL_FILL := Color(1, 1, 1, 0.08)
const LOCKED_MODULATE := Color(1, 1, 1, 0.4)
## Dimmer still, for a slot that cannot be pressed at all rather than one that is
## merely unused.
const UNAVAILABLE_MODULATE := Color(1, 1, 1, 0.2)

const _LEVEL_LABEL_META := &"slot_level_label"

static func slot_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

## One slot, captioned with its 1-based number. Callers add their own press
## handling (and toggle_mode, where slots are a selection rather than an action).
static func create_slot(index: int) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(0, SLOT_HEIGHT)
	# The grid hands each column an equal share of the panel width, so the slots
	# grow with the card instead of sitting in a clump on the left.
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_stylebox_override("normal", slot_style(NORMAL_FILL))
	slot.add_theme_stylebox_override("hover", slot_style(Color(1, 1, 1, 0.16)))
	slot.add_theme_stylebox_override("pressed", slot_style(Color(1, 1, 1, 0.32)))
	slot.add_theme_stylebox_override("disabled", slot_style(Color(1, 1, 1, 0.03)))
	slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	slot.add_child(_caption(index, slot))
	return slot

static func set_level_text(slot: Button, text: String) -> void:
	var label: Label = slot.get_meta(_LEVEL_LABEL_META, null)
	if label != null:
		label.text = text

static func set_locked(slot: Button, locked: bool) -> void:
	slot.modulate = LOCKED_MODULATE if locked else Color.WHITE

## Marks a slot that can be bought right now, so the grid says which of the ten
## are worth a tap instead of making the player select each one to find out.
##
## A border rather than a fill: the fill is what hover and pressed already speak
## with, and overriding it would make an affordable slot look permanently
## half-pressed. A notification dot per slot was the other option and is worse -
## ten dots in a 5x2 grid of 44px buttons reads as a rash, not as news.
##
## Composes with set_locked(), which works through modulate: a locked slot is
## dimmed border and all.
static func set_affordable(slot: Button, affordable: bool, accent: Color) -> void:
	var style := slot_style(NORMAL_FILL)
	if affordable:
		style.set_border_width_all(2)
		style.border_color = accent
	slot.add_theme_stylebox_override("normal", style)

## The slot's own number stays the headline, with the level underneath in a
## smaller, dimmer type so it reads as a subtitle rather than competing with it.
## Button.text can only carry one style, hence the two stacked labels. They
## ignore the mouse so the Button underneath still takes the press, and the VBox
## stretches to the full rect since a Button is not a Container.
static func _caption(index: int, slot: Button) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)

	var lbl_index := Label.new()
	lbl_index.text = str(index + 1)
	lbl_index.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_index.add_theme_font_size_override("font_size", INDEX_FONT_SIZE)
	box.add_child(lbl_index)

	var lbl_level := Label.new()
	lbl_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_level.add_theme_font_size_override("font_size", LEVEL_FONT_SIZE)
	lbl_level.add_theme_color_override("font_color", LEVEL_COLOR)
	box.add_child(lbl_level)
	slot.set_meta(_LEVEL_LABEL_META, lbl_level)

	return box
