@tool
extends Button

@onready var _content: MarginContainer = $MarginContainer

func _ready() -> void:
	# Re-evaluate whenever the hbox's own minimum changes (label text changed, etc.)
	_content.minimum_size_changed.connect(set_custom_min_size)
	set_custom_min_size()

func _get_minimum_size() -> Vector2:
	if not is_node_ready():
		return Vector2.ZERO
	var min_size := _content.get_combined_minimum_size()
	var sb := get_theme_stylebox("normal")
	if sb:
		min_size += Vector2(
			sb.get_content_margin(SIDE_LEFT) + sb.get_content_margin(SIDE_RIGHT),
			sb.get_content_margin(SIDE_TOP) + sb.get_content_margin(SIDE_BOTTOM)
		)
	return min_size

func set_custom_min_size() -> void:
	custom_minimum_size = _get_minimum_size()
