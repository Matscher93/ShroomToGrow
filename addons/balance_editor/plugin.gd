@tool
extends EditorPlugin

## Tools menu entries for tools/balance_editor/server.py.
##
## The server is a separate process, so it outlives a plugin reload but not the
## editor: quitting Godot stops it. Starting it twice is safe — server.py sees
## the port taken by an editor serving this same project and just opens the page.

const SERVER_SCRIPT := "res://tools/balance_editor/server.py"
const URL := "http://127.0.0.1:8765"
const OPEN_ITEM := "Balance Editor"
const STOP_ITEM := "Balance Editor: Stop Server"

var _pid := -1
var _http: HTTPRequest


func _enter_tree() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	add_tool_menu_item(OPEN_ITEM, _open)
	add_tool_menu_item(STOP_ITEM, _stop)


func _exit_tree() -> void:
	remove_tool_menu_item(OPEN_ITEM)
	remove_tool_menu_item(STOP_ITEM)
	# The server is deliberately left running: _exit_tree also fires on a plugin
	# reload, and killing it there would drop the page the user is working in.


func _running() -> bool:
	return _pid != -1 and OS.is_process_running(_pid)


func _open() -> void:
	if _running():
		OS.shell_open(URL)
		return
	var python := "python" if OS.get_name() == "Windows" else "python3"
	var script := ProjectSettings.globalize_path(SERVER_SCRIPT)
	if not FileAccess.file_exists(SERVER_SCRIPT):
		push_error("Balance editor: %s is missing." % SERVER_SCRIPT)
		return
	# server.py opens the browser itself once it is accepting connections, so
	# there is no race between launching it and pointing a browser at the port.
	var pid := OS.create_process(python, [script])
	if pid == -1:
		push_error("Balance editor: could not run '%s' — is it on PATH?" % python)
		return
	_pid = pid
	print("Balance editor starting on %s" % URL)


func _stop() -> void:
	# Asking the server to shut itself down works whoever started it; killing
	# _pid would only cover the runs this plugin launched.
	_http.cancel_request()
	if _http.request(URL + "/api/shutdown", [], HTTPClient.METHOD_POST, "{}") != OK:
		push_error("Balance editor: could not reach %s" % URL)
		return
	_http.request_completed.connect(_on_shutdown_answered, CONNECT_ONE_SHOT)


func _on_shutdown_answered(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("Balance editor: no server answered on %s." % URL)
		return
	_pid = -1
	print("Balance editor stopped.")
