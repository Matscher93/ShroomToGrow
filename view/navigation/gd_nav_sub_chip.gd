extends PanelContainer
## VIEW: one sub-view chip in the bar beside the menu disc - the same destination
## a nav sub-row leads to, laid out to sit in a row rather than a list.
##
## Bound from the same NavSubDestination value object the menu's rows are, so the
## two never disagree about what a screen's sub-views are or which one is up. No
## dot and no subtitle: at this size the accent fill is what says which chip is
## the tab you are on, and a second cue would only cost width.

signal selected(screen_type: ScreenTypes.Types, tab_index: int)

const INACTIVE_LABEL := Color(0.784, 0.847, 0.812)
const BADGE_TEXT := Color(0.043, 0.078, 0.063)
const INACTIVE_CHIP_BG := Color(0.055, 0.102, 0.078, 0.92)
const INACTIVE_CHIP_BORDER := Color(1, 1, 1, 0.08)

@export var lbl_name: Label
@export var panel_badge: PanelContainer
@export var lbl_badge: Label
@export var button: Button

var _screen_type: ScreenTypes.Types
var _tab_index: int

func _ready() -> void:
	button.pressed.connect(_on_pressed)

func bind(sub: NavSubDestination) -> void:
	_screen_type = sub.screen_type
	_tab_index = sub.tab_index
	lbl_name.text = sub.label
	_paint(sub.accent, sub.is_current)
	set_badge(sub.badge_count)

func set_badge(count: int) -> void:
	panel_badge.visible = count > 0
	lbl_badge.text = str(count)

## The chips sit over the screen's own content rather than in a card, so the
## inactive fill is opaque rather than the menu's white wash - a translucent chip
## here reads as part of whatever happens to be scrolling underneath it.
func _paint(accent: Color, is_current: bool) -> void:
	var chip_style := get_theme_stylebox(&"panel") as StyleBoxFlat
	chip_style.bg_color = Color(accent, 0.22) if is_current else INACTIVE_CHIP_BG
	chip_style.border_color = Color(accent, 0.55) if is_current else INACTIVE_CHIP_BORDER

	lbl_name.add_theme_color_override(&"font_color", accent if is_current else INACTIVE_LABEL)

	var badge_style := panel_badge.get_theme_stylebox(&"panel") as StyleBoxFlat
	badge_style.bg_color = accent
	lbl_badge.add_theme_color_override(&"font_color", BADGE_TEXT)

func _on_pressed() -> void:
	selected.emit(_screen_type, _tab_index)
