@tool
extends MarginContainer

@export var ItemColor : Color :
	set(value):
		ItemColor = value
		_update_colors(value)
		
@export var image_background: ColorRect
@export var image_header: ColorRect
@export var label_title: Label
@export var label_amount: Label
		
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_update_colors(ItemColor)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _update_colors(in_color: Color):
	var child := get_node_or_null("ColorRect")
	if is_instance_valid(child):
		image_background._set_color(in_color)
		image_header._set_color(in_color)
		label_title.label_settings.font_color = in_color
		label_amount.label_settings.font_color = in_color
