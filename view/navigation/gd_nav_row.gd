extends PanelContainer
## VIEW: one top-level destination row in the nav menu - icon, name, subtitle and
## an optional count badge.
##
## Bound from a NavDestination value object rather than a live ViewModel: the
## menu is spawned on open and freed on close, so a row never outlives the
## snapshot it was built from. Badge counts are the one thing that can move while
## the menu is up, and those are pushed in through set_badge().

signal selected(screen_type: ScreenTypes.Types)

const INACTIVE_LABEL := Color(0.875, 0.933, 0.902)
const SUBTITLE := Color(0.494, 0.576, 0.529)
const BADGE_TEXT := Color(0.043, 0.078, 0.063)
const INACTIVE_ROW_BG := Color(1, 1, 1, 0.035)
const INACTIVE_ROW_BORDER := Color(1, 1, 1, 0.07)

@export var icon: ColorRect
@export var lbl_name: Label
@export var lbl_subtitle: Label
@export var panel_badge: PanelContainer
@export var lbl_badge: Label
@export var button: Button

var _screen_type: ScreenTypes.Types

func _ready() -> void:
	button.pressed.connect(_on_pressed)

func bind(destination: NavDestination) -> void:
	_screen_type = destination.screen_type
	lbl_name.text = destination.label
	lbl_subtitle.text = destination.subtitle
	lbl_subtitle.visible = not destination.subtitle.is_empty()
	icon.set_icon_shader(destination.icon_shader)
	_paint(destination.accent, destination.is_current)

func set_badge(count: int) -> void:
	panel_badge.visible = count > 0
	lbl_badge.text = str(count)

## The icon tile always carries the destination's accent - the biome icon shaders
## paint their own rounded tile in box_color, and that colour is how a player
## picks a screen out of the list before reading its name.
##
## Which row is the screen you are on rides on the other three cues, all keyed off
## the same accent: fill, border and label. One of them alone reads as decoration
## on a list this dense - together they still carry the current row.
func _paint(accent: Color, is_current: bool) -> void:
	var row_style := get_theme_stylebox(&"panel") as StyleBoxFlat
	row_style.bg_color = Color(accent, 0.1) if is_current else INACTIVE_ROW_BG
	row_style.border_color = Color(accent, 0.3) if is_current else INACTIVE_ROW_BORDER

	icon.set_shader_color(accent)
	lbl_name.add_theme_color_override(&"font_color", accent if is_current else INACTIVE_LABEL)
	lbl_subtitle.add_theme_color_override(&"font_color", SUBTITLE)

	var badge_style := panel_badge.get_theme_stylebox(&"panel") as StyleBoxFlat
	badge_style.bg_color = accent
	lbl_badge.add_theme_color_override(&"font_color", BADGE_TEXT)

func _on_pressed() -> void:
	selected.emit(_screen_type)
