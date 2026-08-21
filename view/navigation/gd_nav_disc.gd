@tool
extends "res://view/base_views/gd_base_shader_button.gd"
## VIEW: the menu disc. One floating button in the thumb corner, present on every
## screen, that opens the nav menu.
##
## Replaces the bottom button bar, and does one thing that bar could not: it is
## tinted to the screen you are on and prints its name, so it doubles as the
## orientation cue the bar used to spend a whole row of tabs on.

@export var _button: Button
## The accent wash and border are painted onto a child rather than onto this
## node: the shader draws one colour at two alphas, so a dark fill under a bright
## accent border needs two layers. This node is the opaque base the child washes
## over, which is what keeps content scrolling underneath from showing through.
@export var shader_panel: PanelContainer
@export var bar_container: BoxContainer
@export var lbl_screen: Label

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
	if property != NavigationViewModel.PROP_DESTINATIONS_CHANGED:
		return
	_refresh()

func _refresh() -> void:
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
