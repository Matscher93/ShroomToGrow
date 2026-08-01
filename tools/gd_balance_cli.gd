extends SceneTree

## Headless bridge between the balance editor and the .tres files.
##
##   godot --headless --script tools/gd_balance_cli.gd -- dump  --out=FILE
##   godot --headless --script tools/gd_balance_cli.gd -- apply  --patch=FILE   --out=FILE [--dry-run]
##   godot --headless --script tools/gd_balance_cli.gd -- create --request=FILE --out=FILE [--dry-run]
##   godot --headless --script tools/gd_balance_cli.gd -- delete --request=FILE --out=FILE [--dry-run]
##
## Results go to --out as JSON, because stdout carries the engine banner and any
## autoload noise. Exit code is non-zero on error.

const BalanceDataScript := preload("res://tools/gd_balance_data.gd")

const DEFAULT_DATA_DIR := "res://data"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var command := ""
	var data_dir := DEFAULT_DATA_DIR
	var patch_path := ""
	var request_path := ""
	var out_path := ""
	var dry_run := false

	for arg: String in args:
		if arg == "--dry-run":
			dry_run = true
		elif arg.begins_with("--data="):
			data_dir = arg.trim_prefix("--data=")
		elif arg.begins_with("--patch="):
			patch_path = arg.trim_prefix("--patch=")
		elif arg.begins_with("--request="):
			request_path = arg.trim_prefix("--request=")
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif not arg.begins_with("-"):
			command = arg

	match command:
		"dump":
			quit(_dump(data_dir, out_path))
		"apply":
			quit(_apply(patch_path, out_path, dry_run))
		"create":
			quit(_create(data_dir, request_path, out_path, dry_run))
		"delete":
			quit(_delete(data_dir, request_path, out_path, dry_run))
		_:
			printerr("usage: gd_balance_cli.gd -- <dump|apply|create|delete> --out=FILE "
				+ "[--patch=FILE] [--request=FILE] [--dry-run]")
			quit(2)


func _dump(data_dir: String, out_path: String) -> int:
	var report := BalanceDataScript.snapshot(data_dir)
	return _write(out_path, report)


func _apply(patch_path: String, out_path: String, dry_run: bool) -> int:
	var patch: Variant = _read_json(patch_path, "apply needs --patch=FILE")
	if typeof(patch) != TYPE_DICTIONARY:
		return 2
	return _write(out_path, BalanceDataScript.apply(patch, dry_run))


func _create(data_dir: String, request_path: String, out_path: String, dry_run: bool) -> int:
	var request: Variant = _read_json(request_path, "create needs --request=FILE")
	if typeof(request) != TYPE_DICTIONARY:
		return 2
	return _write(out_path, BalanceDataScript.create(data_dir, request, dry_run))


func _delete(data_dir: String, request_path: String, out_path: String, dry_run: bool) -> int:
	var request: Variant = _read_json(request_path, "delete needs --request=FILE")
	if typeof(request) != TYPE_DICTIONARY:
		return 2
	return _write(out_path, BalanceDataScript.delete(data_dir, request, dry_run))


func _read_json(path: String, missing: String) -> Variant:
	if path.is_empty():
		printerr(missing)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		printerr("could not read %s" % path)
		return null
	return JSON.parse_string(text)


func _write(out_path: String, report: Dictionary) -> int:
	if out_path.is_empty():
		printerr("missing --out=FILE")
		return 2
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("could not write %s (%s)" % [out_path, error_string(FileAccess.get_open_error())])
		return 2
	file.store_string(JSON.stringify(report))
	file.close()
	for error: Variant in report.get("errors", []):
		printerr("error: %s" % error)
	return 1 if not report.get("errors", []).is_empty() else 0
