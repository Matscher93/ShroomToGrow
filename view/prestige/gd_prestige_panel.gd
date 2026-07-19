extends PanelContainer

@export var dummy_label : Label
@export var button: Button

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	button.pressed.connect(_prestige)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	dummy_label.text = App.preview_biomass_gain()._to_string()

func _prestige() -> void:
	App.prestige()
