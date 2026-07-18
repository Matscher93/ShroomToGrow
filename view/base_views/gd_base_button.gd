extends Button

@export var initial_delay := 0.4  # before repeating starts
@export var repeat_rate := 0.08   # interval while held

var _held_time := 0.0
var _accum := 0.0

func _ready() -> void:
	set_process(false)
	button_down.connect(_on_down)
	button_up.connect(_on_up)

func _on_down() -> void:
	_held_time = 0.0
	_accum = 0.0
	set_process(true)

func _on_up() -> void:
	set_process(false)

func _process(delta: float) -> void:
	_held_time += delta
	if _held_time < initial_delay:
		return
	_accum += delta
	while _accum >= repeat_rate:
		_accum -= repeat_rate
		_fire()

func _fire() -> void:
	pressed.emit()
