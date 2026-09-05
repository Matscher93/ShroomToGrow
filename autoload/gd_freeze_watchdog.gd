class_name FreezeWatchdog
extends Node
## DEBUG: names the phase the main thread was in when it stopped coming back.
##
## A hard lock - nothing drawn, nothing responding - is an endless loop on the
## main thread, and nothing running *on* that thread can report it: every timer,
## signal and _process is behind the loop. So the watching is done from a plain
## Thread, which keeps running while the main thread is wedged, and writes what
## it sees to `user://freeze.log`.
##
## The main thread leaves two things behind for it: a heartbeat, bumped every
## frame, and a breadcrumb naming what it is currently doing (see mark()). When
## the heartbeat stops moving, the last breadcrumb is the phase that hung.
##
## Cheap enough to leave on: one mutex lock per frame plus one per marked phase,
## and the file is only written when something has actually stalled. It is also
## the only way to get anything at all off an Android build, where there is no
## debugger to break into.

## How long the heartbeat may sit still before this counts as a stall rather than
## a slow frame. Well above the worst legitimate frame measured (a screen swap
## with the archive open, ~75ms), and well below the point a player would decide
## the game is dead.
const STALL_MSEC := 3000

## How often the thread looks. Half the poll interval is the worst error on the
## reported stall length, which nobody reads to that precision.
const POLL_MSEC := 500

## Repeat report while a stall continues, so the log says whether the game came
## back or is still wedged - and how long it stayed that way.
const REPEAT_MSEC := 10000

const LOG_PATH := "user://freeze.log"

var _mutex := Mutex.new()
var _thread: Thread
# Every field below is written by the main thread and read by the watcher, so
# both sides take _mutex. GDScript has no atomics, and a torn String read is a
# crash rather than a wrong log line.
var _beat := 0
var _phase := "boot"
var _phase_at := 0
var _stop := false

func _ready() -> void:
	_thread = Thread.new()
	_thread.start(_watch)

## Records what the main thread is about to do. Kept to a handful of coarse
## phases - the point is to tell a hung tick from a hung repaint, not to trace.
func mark(phase: String) -> void:
	_mutex.lock()
	_phase = phase
	_phase_at = Time.get_ticks_msec()
	_mutex.unlock()

func _process(_delta: float) -> void:
	_mutex.lock()
	_beat += 1
	_mutex.unlock()

func _exit_tree() -> void:
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null

# ---------------------------------------------------------------- the watcher

## Runs on its own thread for the life of the game. Sleeps rather than spins, so
## it costs nothing between looks.
func _watch() -> void:
	var last_beat := -1
	var last_beat_at := Time.get_ticks_msec()
	var reported_at := 0
	while true:
		OS.delay_msec(POLL_MSEC)
		_mutex.lock()
		var beat := _beat
		var phase := _phase
		var phase_at := _phase_at
		var stop := _stop
		_mutex.unlock()
		if stop:
			return
		var now := Time.get_ticks_msec()
		if beat != last_beat:
			if reported_at > 0:
				_write("recovered after %d ms, last phase '%s'" % [now - last_beat_at, phase])
				reported_at = 0
			last_beat = beat
			last_beat_at = now
			continue
		var stalled := now - last_beat_at
		if stalled < STALL_MSEC:
			continue
		if reported_at > 0 and now - reported_at < REPEAT_MSEC:
			continue
		reported_at = now
		_write("main thread stalled %d ms in phase '%s' (entered %d ms before the stall)"
			% [stalled, phase, maxi(0, last_beat_at - phase_at)])

## Appends one line, opening and closing per line so a lock that never ends still
## leaves the line on disk.
##
## Also pushed as an error, which is what makes this readable on Android: the
## log file sits in the app's private storage and needs adb to reach, while an
## error goes straight to `adb logcat`.
func _write(line: String) -> void:
	push_error("FreezeWatchdog: %s" % line)
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("%s  %s" % [Time.get_datetime_string_from_system(), line])
	file.close()
