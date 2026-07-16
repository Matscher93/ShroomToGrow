@tool
extends "res://view/offline_income/general_panel_background.gd"

@export var currency_name: Label
@export var currency_change: Label
@export var icon_rect: ColorRect
@export var ColorParam: String
@export var currency_def: CurrencyDef:
	set(value):
		if currency_def:
			currency_def.changed.disconnect(_update_visuals)
		currency_def = value
		if currency_def:
			currency_def.changed.connect(_update_visuals)
		_update_visuals()
		
func _validate_property(property: Dictionary) -> void:
	if property.name != "currency_name" and property.name != "currency_change"\
		and property.name != "ColorParam" and property.name != "icon_rect":
		return
	# Editable only when this scene is the one open on its own in the editor.
	if Engine.is_editor_hint() and get_tree().edited_scene_root != self:
		property.usage &= ~PROPERTY_USAGE_EDITOR
		
func _ready():
	_update_visuals()
	
func _update_visuals() -> void:
	_update_shader()
	if material:
		material.set_shader_parameter(ColorParam, currency_def.main_color)
		
	if currency_name:
		currency_name.text = currency_def.currency_name
		currency_name.label_settings = currency_name.label_settings.duplicate()
		currency_name.label_settings.font_color = currency_def.label_color
		
	if currency_change:
		currency_change.label_settings = currency_change.label_settings.duplicate()
		currency_change.label_settings.font_color = currency_def.currency_color
	
	if icon_rect:
		icon_rect._set_color(currency_def.main_color)

func set_currency_change(change: BigNumber) -> void:
	currency_change.text = "+%s" % [change.to_display()]
