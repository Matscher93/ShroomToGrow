@tool
extends "res://view/base_views/gd_base_shader_button.gd"
## VIEW: the menu disc. One floating button in the thumb corner, present on every
## screen, that opens the nav menu.
##
## Replaces the bottom button bar, and does one thing that bar could not: it is
## tinted to the screen you are on and prints its name, so it doubles as the
## orientation cue the bar used to spend a whole row of tabs on.
##
## It also carries the only cue in the game that reaches across screens: a dot
## when somewhere the player is *not* has work waiting. Everything else - the
## card dots, the top bar chips, the nav badges - only speaks once the player is
## already looking at it, or has the menu open. This is what tells them to look.

## How often the dot re-reads itself on its own.
##
## Missions finish on the wall clock and fire no model signal, so the collectable
## count moves with nothing to notify on (see NavigationViewModel.badge_count).
## The nav menu can live with that - it is opened, read and closed inside a few
## seconds - but the disc is on screen for the whole session, and a dot that
## waits for the player's next tap to appear is a dot they will never connect to
## the thing that caused it. Same shape as the Ruins panel's own clock poll.
const ATTENTION_POLL_INTERVAL := 1.0

@export var _button: Button
## The accent wash and border are painted onto a child rather than onto this
## node: the shader draws one colour at two alphas, so a dark fill under a bright
## accent border needs two layers. This node is the opaque base the child washes
## over, which is what keeps content scrolling underneath from showing through.
@export var shader_panel: PanelContainer
@export var bar_container: BoxContainer
@export var lbl_screen: Label
## Fixed amber rather than the screen accent the rest of the disc wears: this dot
## is about somewhere else, and painting it in the current screen's colour would
## say the opposite. Matches the top bar's chips, which is where the player has
## already learnt what that colour means.
@export var image_notification: ColorRect

var _vm: NavigationViewModel
var _accent := Color.WHITE

func _ready() -> void:
	shader_panel.resized.connect(_update_shader)
	_update_shader()
	_bind_presses()
	# Autoloads aren't instantiated for @tool scripts in the editor, so the
	# ViewModels only exist at runtime.
	if Engine.is_editor_hint():
		return
	bind(App.navigation_vm)
	_start_attention_poll()

## The dot's own clock, for the counts nothing signals. Cheap enough to leave
## running: a tick that finds nothing changed writes the same bool back and stops
## there, and any_attention early-returns on the first screen with work.
func _start_attention_poll() -> void:
	var timer := Timer.new()
	timer.wait_time = ATTENTION_POLL_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_refresh_notification)
	add_child(timer)

func bind(vm: NavigationViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(property: StringName) -> void:
	match property:
		NavigationViewModel.PROP_DESTINATIONS_CHANGED:
			_refresh()
		NavigationViewModel.PROP_BADGES_CHANGED:
			# Nothing the disc paints moved, only what it is waiting on. Repainting
			# the accent and bars for that would be work on every currency tick.
			_refresh_notification()

## Split from _refresh() so a badge change never touches the shader or the label.
func _refresh_notification() -> void:
	if _vm == null:
		return
	image_notification.visible = _vm.any_attention

func _refresh() -> void:
	_refresh_notification()
	_accent = _vm.current_accent
	lbl_screen.text = _vm.current_label
	lbl_screen.add_theme_color_override(&"font_color", _accent)
	for bar in bar_container.get_children():
		var rect := bar as ColorRect
		if rect:
			rect.color = _accent
	_update_shader()

func _wrapped_button() -> Button:
	return _button

func _update_shader() -> void:
	if shader_panel == null or shader_panel.material == null:
		return
	var scale := shader_panel.get_global_transform().get_scale()
	shader_panel.material.set_shader_parameter("rect_size", shader_panel.size * scale)
	shader_panel.material.set_shader_parameter(color_param, _state_color())

func _state_color() -> Color:
	return _accent
