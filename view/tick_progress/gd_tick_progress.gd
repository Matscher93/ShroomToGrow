extends PanelContainer

@export var progress_rect : ColorRect
@export var lbl_time_left : Label
@export var lbl_time_per_tick : Label
var tick_timer: Timer

func _ready() -> void:
	tick_timer = App.tick_timer

func _process(_delta: float) -> void:
	var time_left = tick_timer.time_left
	var tick_duration = tick_timer.wait_time
	progress_rect.material.set_shader_parameter("tick_progress", 1.0 - time_left/tick_duration)
	lbl_time_left.text = "%.1fs" % [time_left]
	lbl_time_per_tick.text = " / %.1fs" % [tick_duration]
