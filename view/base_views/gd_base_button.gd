extends Button
## VIEW: a button that keeps firing while it is held down, for the actions a
## player buys dozens of in a row - node tiers, Biome Size, biome upgrades,
## boost levels, automation levels, and claiming a stack of achievement
## tiers.
##
## The repeat accelerates: it opens at repeat_rate and ramps to min_repeat_rate
## over ramp_time, so a short hold stays controllable and a long one clears a
## hundred levels without the player counting them out. Releasing resets the
## ramp, so a deliberate single tap is never sped up.
##
## Repeats by re-emitting [signal pressed], so a view binds to it exactly as it
## would a plain Button and needs to know nothing about the hold.

## Emitted alongside `pressed` for the repeats only, never for the release that
## Button emits on its own. Wrappers that re-emit a press from `button_up` (see
## gd_base_shader_button.gd) listen to this instead of `pressed`, which would
## double-count that release.
signal repeated()

@export var initial_delay := 0.4    # before repeating starts
@export var repeat_rate := 0.08     # interval at the start of a hold
@export var min_repeat_rate := 0.01 # fastest interval a long hold reaches
@export var ramp_time := 2.0        # seconds of repeating to reach min_repeat_rate

## Floor on the interval, so a min_repeat_rate authored at 0 cannot turn the
## catch-up loop below into an infinite one.
const _MIN_INTERVAL := 0.001

## Most repeats one frame may fire. Only reached when a frame ran long (a stall,
## a scene swap); without it the catch-up would spend the whole lost frame at
## once, and at the ramped-up rate that is dozens of purchases the player never
## asked for.
const _MAX_FIRES_PER_FRAME := 8

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
	# Godot clears a button's pressed state when it is disabled but emits no
	# button_up for it, so the hold that ran the player out of currency would
	# otherwise leave this repeating forever - and fire again the moment they
	# could afford the next one, without touching the button.
	if disabled:
		set_process(false)
		return
	_held_time += delta
	if _held_time < initial_delay:
		return
	_accum += delta
	var interval := _current_interval()
	var fired := 0
	while _accum >= interval and fired < _MAX_FIRES_PER_FRAME:
		_accum -= interval
		fired += 1
		_fire()
	if fired >= _MAX_FIRES_PER_FRAME:
		_accum = 0.0  # drop the backlog rather than paying it out next frame

## Interval between repeats right now, easing from repeat_rate down to
## min_repeat_rate across ramp_time of held-down repeating.
func _current_interval() -> float:
	var repeating_for := _held_time - initial_delay
	var progress := 1.0 if ramp_time <= 0.0 else clampf(repeating_for / ramp_time, 0.0, 1.0)
	return maxf(_MIN_INTERVAL, lerpf(repeat_rate, min_repeat_rate, progress))

func _fire() -> void:
	pressed.emit()
	repeated.emit()
