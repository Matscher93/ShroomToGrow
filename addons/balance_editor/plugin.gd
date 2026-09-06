@tool
extends EditorPlugin

## Tools menu entries for tools/balance_editor/server.py.
##
## The server is a separate process, so it outlives a plugin reload but not the
## editor: quitting Godot stops it.
##
## Pressing "Balance Editor" always gets a *fresh* server: one already on the
## port is asked to shut down first, and the new one is only launched once the
## port is actually free. Restarting rather than reusing because the server
## caches - a snapshot of every resource, and the derived reports behind
## /api/curves and /api/perks - and it holds the Python and JavaScript of the
## editor itself in memory. An editor left running from before an edit to any of
## those serves the old ones with nothing to say it is doing so, which is a
## confusing way to lose an afternoon.
##
## Whether a server is there is decided by asking it, not by remembering a pid:
## the one on the port is just as likely to have been started from a terminal.

const SERVER_SCRIPT := "res://tools/balance_editor/server.py"
const URL := "http://127.0.0.1:8765"
const OPEN_ITEM := "Balance Editor"
const STOP_ITEM := "Balance Editor: Stop Server"

## How long to keep waiting for a stopping server to let go of the port, and how
## often to look. server.py defers its own shutdown by 0.2s so the reply reaches
## the caller first, so there is always at least one poll's worth of waiting.
const STOP_TIMEOUT_SECONDS := 5.0
const STOP_POLL_SECONDS := 0.2

var _http: HTTPRequest
## One menu press at a time. HTTPRequest carries a single request, and both menu
## items are several of them in a row.
var _busy := false


func _enter_tree() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	add_tool_menu_item(OPEN_ITEM, _open)
	add_tool_menu_item(STOP_ITEM, _stop)


func _exit_tree() -> void:
	remove_tool_menu_item(OPEN_ITEM)
	remove_tool_menu_item(STOP_ITEM)
	# The server is left running: _exit_tree also fires on a plugin reload, and
	# killing it there would drop the page the user is working in.


#region Menu items

func _open() -> void:
	if _busy:
		return
	_busy = true
	await _restart()
	_busy = false


func _stop() -> void:
	if _busy:
		return
	_busy = true
	# Asking the server to shut itself down works whoever started it, which
	# killing a remembered pid would not.
	if await _shutdown_running():
		print("Balance editor stopped.")
	_busy = false

#endregion


#region Restart

## Replaces whatever is on the port with a server started now.
func _restart() -> void:
	var running := await _identify()
	if running.get("foreign", false):
		# Not ours to stop. server.py refuses the same case for the same reason.
		push_error("Balance editor: something else is already on %s. Stop it first."
			% URL)
		return
	if running.get("other_project", "") != "":
		push_error("Balance editor: %s is serving a different project (%s). Stop it first."
			% [URL, running["other_project"]])
		return

	if running.get("ours", false):
		print("Balance editor: restarting the server on %s…" % URL)
		if not await _shutdown_running():
			return
		if not await _wait_for_port():
			push_error("Balance editor: the old server is still on %s after %ds."
				% [URL, STOP_TIMEOUT_SECONDS])
			return

	_launch()


## What is on the port, as one of four answers: nothing, `ours` (this project),
## `other_project` (the editor, elsewhere), or `foreign` (not the editor at all).
##
## GET /api/files is the same probe server.py runs before it decides a second
## copy of itself is a request for the page rather than an error, so the two
## agree on what counts as "already running".
func _identify() -> Dictionary:
	var answer := await _request("/api/files", HTTPClient.METHOD_GET)
	if not answer["ok"]:
		return {}                  # nothing answered: the port is free
	if answer["code"] != 200:
		return {"foreign": true}

	var parsed: Variant = JSON.parse_string(answer["body"])
	if not parsed is Dictionary or not parsed.has("project"):
		return {"foreign": true}
	var project: String = parsed["project"]
	if project != _project_root():
		return {"other_project": project}
	return {"ours": true}


## Where this project lives, in the shape server.py reports it: an absolute path
## with no trailing separator (it sends a resolved pathlib.Path).
func _project_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")


## Asks the server on the port to stop. True when one answered.
func _shutdown_running() -> bool:
	var answer := await _request("/api/shutdown", HTTPClient.METHOD_POST, "{}")
	if not answer["ok"] or answer["code"] != 200:
		push_warning("Balance editor: no server answered on %s." % URL)
		return false
	return true


## Waits until nothing answers on the port any more, so the new server binds
## instead of finding it taken and quietly opening the old page.
func _wait_for_port() -> bool:
	var deadline := Time.get_ticks_msec() + int(STOP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(STOP_POLL_SECONDS).timeout
		var answer := await _request("/api/files", HTTPClient.METHOD_GET)
		if not answer["ok"]:
			return true
	return false


func _launch() -> void:
	if not FileAccess.file_exists(SERVER_SCRIPT):
		push_error("Balance editor: %s is missing." % SERVER_SCRIPT)
		return
	var python := "python" if OS.get_name() == "Windows" else "python3"
	var script := ProjectSettings.globalize_path(SERVER_SCRIPT)
	# server.py opens the browser itself once it accepts connections, so there is
	# no race between launching it and pointing a browser at the port.
	if OS.create_process(python, [script]) == -1:
		push_error("Balance editor: could not run '%s' — is it on PATH?" % python)
		return
	print("Balance editor starting on %s" % URL)

#endregion


## One request, awaited: { "ok": bool, "code": int, "body": String }.
##
## `ok` is whether anything answered at all, which is what tells "no server
## there" apart from "a server said no" - the whole probe rests on that
## difference.
func _request(path: String, method: int, body: String = "") -> Dictionary:
	_http.cancel_request()
	if _http.request(URL + path, PackedStringArray(), method, body) != OK:
		return {"ok": false, "code": 0, "body": ""}
	var answer: Array = await _http.request_completed
	return {
		"ok": answer[0] == HTTPRequest.RESULT_SUCCESS,
		"code": answer[1],
		"body": (answer[3] as PackedByteArray).get_string_from_utf8(),
	}
