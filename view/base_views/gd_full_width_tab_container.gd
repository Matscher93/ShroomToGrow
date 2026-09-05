class_name FullWidthTabContainer
extends TabContainer
## VIEW: a TabContainer whose visible tabs are padded out to fill the whole bar.
##
## Godot's tab_alignment only offers left, centre and right - there is no "fill",
## and no per-tab width to set - so the tabs cluster at whichever end and leave
## most of the bar empty. The one lever a TabBar does give is the content margin
## on its tab styleboxes, which is shared by every tab, so widening it evenly is
## what spreads them across the width.
##
## Tabs end up sized to their own title plus the same padding either side, rather
## than all exactly equal: one shared stylebox cannot say anything per tab. What
## it does guarantee is that the row ends where the bar ends.
##
## The styleboxes are duplicated before anything is written to them. The ones
## get_theme_stylebox() hands back belong to the theme itself, and every TabBar in
## the app draws from those - mutating one in place would repad all of them.

## Left unclaimed at the right-hand end. The title widths are measured off the
## font rather than read back from the TabBar, so they can land a fraction wide;
## without this the row would occasionally overflow by a pixel and the bar would
## grow its scroll arrows.
const _SAFETY_MARGIN := 2.0

## The tab states that draw a stylebox behind a title. All four are padded by the
## same amount so a tab does not resize as it is selected or hovered.
const _TAB_STYLES: Array[StringName] = [
	&"tab_selected", &"tab_unselected", &"tab_hovered", &"tab_disabled",
]

var _tab_bar: TabBar
var _styles: Array[StyleBox] = []
## What was last written, so a re-layout that changes nothing writes nothing. An
## override write re-sorts this container, which is what calls back in here.
var _applied_margin := -1.0
## Writes made in the frame `_writes_frame` names, so a padding that never
## settles costs a few passes instead of the whole game.
##
## The measurement above is what makes the loop terminate - the margin is a
## function of a width it cannot move, so the second pass computes the same
## number and the equality check stops it. This is the backstop for the case that
## reasoning misses: an ancestor that sizes itself to the bar would put the
## feedback back, and a margin alternating between two values slips past an
## equality check. A few frames of padding half a pixel out is a bug report; a
## frozen game is the one this class already caused.
var _writes_this_frame := 0
var _writes_frame := -1
const _MAX_WRITES_PER_FRAME := 4

func _ready() -> void:
	_tab_bar = get_tab_bar()
	for style_name in _TAB_STYLES:
		_styles.append(_tab_bar.get_theme_stylebox(style_name, &"TabBar").duplicate())
	# The tab bar's own signal, not this container's: the container is resized
	# first and lays its children out afterwards, so on its own `resized` the bar
	# is still the width it was and the tabs come out padded for the last size.
	_tab_bar.resized.connect(spread_tabs)
	spread_tabs()

## Repads the visible tabs to fill the bar. Called for you on resize; call it by
## hand after set_tab_hidden(), which changes how many tabs share the width
## without changing the bar's size, so nothing else announces it.
func spread_tabs() -> void:
	if _styles.is_empty():
		return
	# Nothing to spread across yet. A screen MenuWarmup preloads is laid out
	# before it is ever shown, so this container has no width and the bar falls
	# back to its own minimum - which is a width the padding below sets, not one
	# it can be measured against. The real `resized` lands once the screen is on
	# screen and repads it then.
	if size.x <= 0.0:
		return
	var font := _tab_bar.get_theme_font(&"font")
	if font == null:
		return
	var font_size := _tab_bar.get_theme_font_size(&"font_size")
	var shown := 0
	var titles_width := 0.0
	for i in range(_tab_bar.tab_count):
		if _tab_bar.is_tab_hidden(i):
			continue
		shown += 1
		titles_width += font.get_string_size(_tab_bar.get_tab_title(i),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if shown == 0:
		return
	var gaps := float(_tab_bar.get_theme_constant(&"tab_separation") * (shown - 1))
	# This container's width, and never the bar's. The padding *is* what sets the
	# bar's width - a padded tab raises the bar's minimum - so measuring against
	# the bar feeds the last write back in as the next input: the margin widens
	# the bar, the wider bar buys more margin, and the pair climb until the game
	# is spinning inside its own layout with nothing left to draw a frame with.
	# That was a hard lock, reachable whenever a tab was hidden (which drops the
	# bar's width below this container's, opening the gap the loop climbs).
	# The container's width is the one input the padding cannot move.
	var spare := size.x - titles_width - gaps - _SAFETY_MARGIN
	# Halved because the padding sits on both sides of every title. Floored so the
	# row can only ever come up short of the bar, never overrun it.
	var margin := floorf(maxf(0.0, spare) / float(shown * 2))
	if is_equal_approx(margin, _applied_margin):
		return
	var frame := Engine.get_process_frames()
	if frame != _writes_frame:
		_writes_frame = frame
		_writes_this_frame = 0
	if _writes_this_frame >= _MAX_WRITES_PER_FRAME:
		return
	_writes_this_frame += 1
	_applied_margin = margin
	for i in range(_TAB_STYLES.size()):
		var style := _styles[i]
		style.content_margin_left = margin
		style.content_margin_right = margin
		# Re-added rather than only mutated: TabBar measures its tabs from a theme
		# cache it refills on a theme change, and a stylebox edited in place
		# repaints without ever moving those widths.
		_tab_bar.add_theme_stylebox_override(_TAB_STYLES[i], style)
