class_name PressGuard
extends Node
## VIEW base: holds structural refreshes back while the player has the pointer
## down, and runs them the moment it comes up.
##
## A list that frees and respawns its rows on a ViewModel notification tears the
## Button that captured the press out of the tree, and the release then lands on
## nothing - the tap is silently swallowed. A refresh that only resizes a row eats
## the tap the same way, more quietly: Godot cancels a release whose position is
## outside the button's rect, so a row that grew a badge digit under the finger
## never fires. Both are on a fixed cadence, because the game ticks while the
## finger is down - which is exactly the window a player spends tapping.
##
## Nothing is dropped. The work is keyed, so a burst of notifications during one
## hold collapses to a single run on release, and a view that is freed mid-hold
## takes its queue with it.
##
## Only *structural* work belongs here - spawning, freeing, visibility, anything
## that reflows. Labels and counters keep repainting live, so a held buy button
## still shows its level climbing while the guard sits on the rebuild.
##
## Held is read off the global pointer rather than tracked per Button: the cards
## these lists spawn own their buttons privately, and with
## `emulate_mouse_from_touch` on - the project default - one read covers touch as
## well as mouse.

## StringName -> {work: Callable, defer: bool}. One entry per kind of work, so the
## last request under a key wins rather than the queue growing with every
## notification.
var _queued: Dictionary = {}

var is_held: bool:
	get: return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _ready() -> void:
	set_process(false)

## Runs `work` now if the pointer is free, otherwise queues it under `key` for the
## first frame after release.
##
## `defer` is for the callers that could not run inline even with nothing held:
## the nav rebuilds arrive from inside a row's own `pressed` emission, and freeing
## that row out from under the handler still running in it is what the deferral
## has always been there to avoid. Everything else refreshes in place, as it did
## before the guard existed - a held pointer is the only thing that delays it.
func run_when_free(key: StringName, work: Callable, defer: bool = false) -> void:
	if not is_held:
		if defer:
			work.call_deferred()
		else:
			work.call()
		return
	_queued[key] = {"work": work, "defer": defer}
	set_process(true)

func _process(_delta: float) -> void:
	if is_held:
		return
	set_process(false)
	# Taken and cleared before running: the work can queue more of its own, and
	# that belongs to the next flush rather than to this one.
	var pending := _queued.duplicate()
	_queued.clear()
	for key: StringName in pending:
		var entry: Dictionary = pending[key]
		var work: Callable = entry["work"]
		if not work.is_valid():
			continue
		if entry["defer"]:
			work.call_deferred()
		else:
			work.call()
