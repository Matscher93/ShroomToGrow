extends PanelContainer
## VIEW: one indented sub-view row under a nav destination. A dot rather than an
## icon: the parent row's icon already says which screen this belongs to, and a
## second glyph at this size only adds noise.

signal selected(screen_type: ScreenTypes.Types, tab_index: int)

const INACTIVE_LABEL := Color(0.784, 0.847, 0.812)
const INACTIVE_DOT := Color(1, 1, 1, 0.22)
const BADGE_TEXT := Color(0.043, 0.078, 0.063)
const INACTIVE_ROW_BG := Color(1, 1, 1, 0.03)
const INACTIVE_ROW_BORDER := Color(1, 1, 1, 0.06)

@export var dot: PanelContainer
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

func _paint(accent: Color, is_current: bool) -> void:
	var row_style := get_theme_stylebox(&"panel") as StyleBoxFlat
	row_style.bg_color = Color(accent, 0.13) if is_current else INACTIVE_ROW_BG
	row_style.border_color = Color(accent, 0.3) if is_current else INACTIVE_ROW_BORDER

	var dot_style := dot.get_theme_stylebox(&"panel") as StyleBoxFlat
	dot_style.bg_color = accent if is_current else INACTIVE_DOT

	lbl_name.add_theme_color_override(&"font_color", accent if is_current else INACTIVE_LABEL)

	var badge_style := panel_badge.get_theme_stylebox(&"panel") as StyleBoxFlat
	badge_style.bg_color = accent
	lbl_badge.add_theme_color_override(&"font_color", BADGE_TEXT)

func _on_pressed() -> void:
	selected.emit(_screen_type, _tab_index)
