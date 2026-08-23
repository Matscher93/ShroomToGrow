extends GdUnitTestSuite
## The write guard in SaveManager (autoload/gd_save_manager.gd).
##
## A save this build declines to apply - one from a newer build, or one that no
## longer parses - leaves the game running as a fresh start. Before the guard,
## the autosave then committed that fresh start over the file the load had just
## refused to touch, and the write after it rotated the fresh save into the
## backup as well, so both copies were gone inside thirty seconds. The refusal
## to load is only worth anything if nothing overwrites the file afterwards.
##
## The instance under test is built directly rather than via the autoload, so
## load_game() can be driven repeatedly. The live autoload is frozen for the
## duration with the same flag: its own fifteen-second autosave shares these
## paths and would otherwise land in the middle of a test.

const NEWER_SAVE := '{"version": 999, "saved_at": 0.0, "game": {}}'
const UNPARSEABLE_SAVE := "{not json at all"

var _manager: Node
var _saved_primary: String
var _saved_backup: String
var _autoload_was_blocked: bool

func before_test() -> void:
	_manager = auto_free(load("res://autoload/gd_save_manager.gd").new())
	# Freeze the real autoload: it writes these same two paths on a timer.
	_autoload_was_blocked = SaveManager.load_blocked
	SaveManager.load_blocked = true
	_saved_primary = _read_raw(SaveManager.SAVE_PATH)
	_saved_backup = _read_raw(SaveManager.BACKUP_PATH)

func after_test() -> void:
	_restore(SaveManager.SAVE_PATH, _saved_primary)
	_restore(SaveManager.BACKUP_PATH, _saved_backup)
	SaveManager.load_blocked = _autoload_was_blocked

func _read_raw(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

## Puts back exactly what was there, including "there was nothing".
func _restore(path: String, text: String) -> void:
	if text.is_empty():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	_write_raw(path, text)

func _clear_saves() -> void:
	for path in [SaveManager.SAVE_PATH, SaveManager.BACKUP_PATH, SaveManager.TMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

# ─── What blocks ─────────────────────────────────────────────────────────────

func test_a_save_from_a_newer_build_blocks_saving() -> void:
	_clear_saves()
	_write_raw(SaveManager.SAVE_PATH, NEWER_SAVE)

	_manager.load_game()

	assert_bool(_manager.load_blocked).is_true()
	assert_str(_manager.load_blocked_reason).is_not_empty()

func test_a_save_that_no_longer_parses_blocks_saving() -> void:
	# _read() answers {} for this and for a missing file alike, so the guard has
	# to tell them apart by whether a file was on disk at all.
	_clear_saves()
	_write_raw(SaveManager.SAVE_PATH, UNPARSEABLE_SAVE)

	_manager.load_game()

	assert_bool(_manager.load_blocked).is_true()

func test_an_unreadable_primary_with_an_unreadable_backup_blocks_saving() -> void:
	_clear_saves()
	_write_raw(SaveManager.SAVE_PATH, UNPARSEABLE_SAVE)
	_write_raw(SaveManager.BACKUP_PATH, UNPARSEABLE_SAVE)

	_manager.load_game()

	assert_bool(_manager.load_blocked).is_true()

# ─── What does not block ─────────────────────────────────────────────────────

func test_no_save_at_all_is_a_fresh_start_and_still_saves() -> void:
	# The first launch on a new device. Nothing is at risk, so the autosave has to
	# keep working - a guard that fires here would mean the game never saves.
	_clear_saves()

	_manager.load_game()

	assert_bool(_manager.load_blocked).is_false()

# ─── What the block actually prevents ────────────────────────────────────────

func test_the_refused_save_is_still_on_disk_after_a_save_attempt() -> void:
	# The regression itself: refuse the file, then let the autosave fire.
	_clear_saves()
	_write_raw(SaveManager.SAVE_PATH, NEWER_SAVE)
	_manager.load_game()

	_manager.save_game()
	_manager.save_game()   # the second write is what used to take the backup too

	assert_str(_read_raw(SaveManager.SAVE_PATH)).is_equal(NEWER_SAVE)
	assert_bool(FileAccess.file_exists(SaveManager.BACKUP_PATH)) \
		.override_failure_message("A blocked save must not rotate anything into the backup.") \
		.is_false()

func test_save_game_does_not_record_a_write_it_did_not_make() -> void:
	# last_savegame is what offline progress is measured from, so a blocked save
	# advancing it would date the next gap from a write that never landed.
	_manager._block_saving("test")

	_manager.save_game()

	assert_dict(_manager.last_savegame).is_empty()

func test_blocking_records_a_reason_for_the_ui() -> void:
	_manager._block_saving("because")

	assert_bool(_manager.load_blocked).is_true()
	assert_str(_manager.load_blocked_reason).is_equal("because")
