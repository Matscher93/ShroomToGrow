class_name UpgradeDefLoader
extends RefCounted
## MODEL: locates the authored UpgradeDef resources on disk.
##
## Shared by App's startup wiring and the data-integrity tests, so a test
## validates against exactly the set the game registers rather than its own copy
## of the walk.

const SYMBIOSIS_PATH := "res://data/upgrades/symbiosis/"
const PRESTIGE_PATH := "res://data/upgrades/prestige/"
const BIOME_PATH := "res://data/upgrades/biomes/"

## Recursively loads every UpgradeDef .tres under path. Other resource types in
## the tree (UpgradeEffectDef, ScalingSourceDef) are skipped.
static func load_all(path: String) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Could not open %s (%s)" % [path, DirAccess.get_open_error()])
		return defs
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			defs.append_array(load_all(full_path))
		elif file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			# Packed builds list resources as "<name>.tres.remap". The real
			# resource lives at the path with ".remap" stripped.
			var res := load(full_path.trim_suffix(".remap"))
			if res is UpgradeDef:
				defs.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	return defs
