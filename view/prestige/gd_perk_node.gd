@tool
class_name PerkNode
extends Control
## VIEW: single perk node in the mycelial web. A circular button (drawn by
## sh_perk_node.gdshader on "background") plus non-interactive name and level
## labels beneath it. PerkWeb positions and sizes this root against NODE_SIZE,
## which matches "background" exactly, so the labels hang off the bottom.
##
## The labels sit in a VBox of a fixed width and the name wraps inside it, so a
## long perk name grows downward into empty space instead of sideways over its
## neighbours. Both halves of that matter: perk_node_test.gd pins the width
## against the tightest node spacing PerkTree can produce, and the stacking is
## what keeps a wrapped second line off the level label.

signal pressed

enum Status { LOCKED, AVAILABLE, UNLOCKED, SELECTED }

@export var background: PanelContainer
@export var button: Button
@export var name_label: Label
@export var level_label: Label

@export var locked_ring_thickness: float = 0.05
@export var available_ring_thickness: float = 0.05
@export var unlocked_ring_thickness: float = 0.05
@export var selected_ring_thickness: float = 0.12

var def: PerkDef

func _ready() -> void:
	button.pressed.connect(func() -> void: pressed.emit())

func bind(in_def: PerkDef) -> void:
	def = in_def
	button.focus_mode = Control.FOCUS_NONE
	name_label.text = def.display_name

func refresh(vm: PerkViewModel, selected: bool) -> void:
	var status := Status.LOCKED
	var ring_thickness := locked_ring_thickness
	match vm.status:
		"available":
			status = Status.AVAILABLE
			ring_thickness = available_ring_thickness
		"owned":
			status = Status.UNLOCKED
			ring_thickness = unlocked_ring_thickness
	if selected:
		status = Status.SELECTED
		ring_thickness = selected_ring_thickness
	if background.material is ShaderMaterial:
		background.material.set_shader_parameter("status", status)
		background.material.set_shader_parameter("ring_thickness", ring_thickness)
	level_label.text = vm.level_text
	button.tooltip_text = vm.tooltip_text

func set_color(color: Color) -> void:
	if background.material is ShaderMaterial:
		background.material.set_shader_parameter("button_color", color)

## PerkWeb zooms "world", so the shader only sees unit-size UVs and needs the
## canvas zoom to keep screen-space detail consistent. Same reason PerkConnector
## forwards it to sh_line.gdshader.
func set_zoom(zoom: float) -> void:
	if background.material is ShaderMaterial:
		background.material.set_shader_parameter("scale", zoom)
