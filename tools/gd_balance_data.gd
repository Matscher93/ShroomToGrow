class_name BalanceData
extends RefCounted

## Reads the authored `.tres` balance data under `res://data` into a tabular
## snapshot, and writes edits back into those same files.
##
## Nothing here regenerates a resource. `apply()` loads the file a row belongs
## to, sets properties on that live instance and re-saves it, which keeps the
## uid, the `[ext_resource]` links and the element type of typed arrays
## (`Array[UpgradeEffectDef]`) intact.
##
## The snapshot is tabular (one table per resource class, one column per
## `@export` property) because that is the shape the editor renders.

const KEY_COLUMN := "res_path"
const LIST_SEPARATOR := "|"

## Resources whose script lives here are tooling, not balance data.
const SKIPPED_SCRIPT_PREFIX := "res://addons/"

## Files opened during one operation, so every reference to a sub-resource
## resolves to the same live instance the rest of the run is mutating.
static var _open_files: Dictionary[String, Resource] = {}

## file path -> { "file.tres::id": Resource }, built the moment a file is opened.
static var _subresources: Dictionary[String, Dictionary] = {}


#region Snapshot

## Returns { "data": { "UpgradeDef": { "header": [...], "rows": [[...]] } },
##           "errors": [...] }.
static func snapshot(data_dir: String) -> Dictionary:
	var errors: Array = []
	var by_class: Dictionary[String, Array] = {}
	_open_files.clear()
	_subresources.clear()

	for path: String in _collect_resource_paths(data_dir):
		var res := _load_file(path)
		if res == null:
			errors.append("could not load %s" % path)
			continue
		var found: Array[Resource] = []
		var seen: Dictionary[int, bool] = {}
		_expand_subresources(res, path, found, seen)
		for row: Resource in found:
			var script: Script = row.get_script()
			if script == null or script.resource_path.begins_with(SKIPPED_SCRIPT_PREFIX):
				continue
			var class_key := _class_key(script)
			if not by_class.has(class_key):
				by_class[class_key] = []
			by_class[class_key].append(row)

	var tables := {}
	for class_key: String in by_class:
		var resources: Array = by_class[class_key]
		resources.sort_custom(func(a: Resource, b: Resource) -> bool:
			return a.resource_path < b.resource_path)

		var columns := _exportable_properties(resources[0])
		var header := [KEY_COLUMN]
		var meta := [{"name": KEY_COLUMN, "type": "key"}]
		for column: Dictionary in columns:
			header.append(column.name)
			meta.append(_column_meta(column))

		var rows := []
		for res: Resource in resources:
			var line := [res.resource_path]
			for column: Dictionary in columns:
				line.append(encode_value(res.get(column.name), column))
			rows.append(line)
		tables[class_key] = {
			"header": header,
			"columns": meta,
			"script": (resources[0].get_script() as Script).resource_path,
			"rows": rows,
		}

	return {"data": tables, "errors": errors}

#endregion


#region Curves

## Levels sampled for a def with no max_level of its own (0 = infinite).
const CURVE_OPEN_ENDED_LEVELS := 50

## Id the throwaway UpgradeDef is registered under while sampling. '#' never
## appears in an authored id, so it cannot collide with one.
const CURVE_ID := &"#curve"


## Cost and effect per level for every priced def under `data_dir`.
##
## Sampled through the live game code - UpgradeSystem.cost() and
## UpgradeEffectDef.magnitude() - rather than a copy of their formulas, so the
## editor can draw these behind its own curve and make any drift visible.
##
## Returns { "curves": { res_path: { "max_level": int,
##                                   "cost": [[mantissa, exponent], ...],
##                                   "effect": [[mantissa, exponent], ...],
##                                   "stat": "...", "op": "...", ... } },
##           "errors": [...] }
##
## `cost[i]` is what buying the *next* level costs while sitting at level i,
## matching what the game charges; `effect[i]` is the total magnitude at level i.
static func curves(data_dir: String) -> Dictionary:
	var out := {}
	var errors: Array = []
	_open_files.clear()
	_subresources.clear()
	# A perk with no effects of its own runs on its branch's, so sampling it
	# without them would report a flat zero for most of the web.
	var fallbacks := _perk_effect_fallbacks()

	for path: String in _collect_resource_paths(data_dir):
		var res := _load_file(path)
		if res == null:
			errors.append("could not load %s" % path)
			continue
		var found: Array[Resource] = []
		var seen: Dictionary[int, bool] = {}
		_expand_subresources(res, path, found, seen)
		for row: Resource in found:
			if not _is_priced(row):
				continue
			out[row.resource_path] = curve_for(row, fallbacks.get(row.resource_path, []))
	return {"curves": out, "errors": errors}


## PerkNodeDef path -> the default_effects of the branch it grows on, the same
## fallback PerkBranchDef.effects_for() applies at build time.
static func _perk_effect_fallbacks() -> Dictionary:
	var out := {}
	var branch_list := load(PERK_BRANCHES_PATH) as PerkBranchList
	if branch_list == null:
		return out
	for branch: PerkBranchDef in branch_list.branches:
		if branch.default_effects.is_empty():
			continue
		for root: PerkNodeDef in branch.roots:
			_spread_fallback(root, branch.default_effects, out)
	return out


static func _spread_fallback(node: PerkNodeDef, effects: Array, out: Dictionary) -> void:
	if node == null:
		return
	out[node.resource_path] = effects
	for child: PerkNodeDef in node.children:
		_spread_fallback(child, effects, out)


## True for anything the cost formula can be run on: an UpgradeDef or a
## PerkNodeDef, without this file needing to know which classes those are.
static func _is_priced(res: Resource) -> bool:
	var properties := _properties_by_name(res)
	return properties.has(&"cost_growth") and properties.has(&"_base_cost_mantissa")


## One def's sampled curve. `fallback_effects` stands in when the def declares
## none of its own, mirroring PerkBranchDef.effects_for().
static func curve_for(res: Resource, fallback_effects: Array) -> Dictionary:
	var properties := _properties_by_name(res)
	var max_level: int = res.get(&"max_level") if properties.has(&"max_level") else 0
	var samples := max_level if max_level > 0 else CURVE_OPEN_ENDED_LEVELS

	# A one-def UpgradeSystem is the only way to price a level through the real
	# cost(), which reads the level out of its own table.
	var system := UpgradeSystem.new()
	var def := UpgradeDef.new()
	def.id = CURVE_ID
	def.base_cost = res.get(&"base_cost")
	def.cost_growth = res.get(&"cost_growth")
	if properties.has(&"cost_growth_exponent"):
		def.cost_growth_exponent = res.get(&"cost_growth_exponent")
	system.register(def)

	var own_effects: Array = res.get(&"effects") if properties.has(&"effects") else []
	var effects: Array = own_effects if not own_effects.is_empty() else fallback_effects
	var effect: UpgradeEffectDef = effects[0] if not effects.is_empty() else null

	var costs: Array = []
	var magnitudes: Array = []
	for level in range(samples + 1):
		system.from_save({String(CURVE_ID): level})
		costs.append(_big_pair(system.cost(CURVE_ID)))
		magnitudes.append(_big_pair(effect.magnitude(level)) if effect else [0.0, 0])

	var curve := {
		"max_level": max_level,
		"samples": samples,
		"cost": costs,
		"effect": magnitudes,
		"cost_growth": def.cost_growth,
		"cost_growth_exponent": def.cost_growth_exponent,
	}
	if effect:
		curve["stat"] = String(effect.stat)
		curve["op"] = _enum_key(UpgradeEffectDef.Op, effect.op)
		curve["scope"] = _enum_key(UpgradeEffectDef.Scope, effect.scope)
		curve["target"] = String(effect.target)
		curve["per_level"] = effect.per_level
		curve["level_scaling"] = _enum_key(UpgradeEffectDef.LevelScaling, effect.level_scaling)
		curve["effect_count"] = effects.size()
	return curve


static func _big_pair(value: BigNumber) -> Array:
	return [value.mantissa, value.exponent]


## Name of an enum value, for readable JSON. `values` is the enum dictionary
## itself (`UpgradeEffectDef.Op`), so a reordered enum can't mislabel anything.
static func _enum_key(values: Dictionary, value: int) -> String:
	for key: String in values:
		if values[key] == value:
			return key
	return str(value)

#endregion


#region Perks

const PERK_BRANCHES_PATH := "res://data/prestige/all_branches.tres"


## The prestige web as the game builds it, with the two numbers no table can
## show: what maxing a perk costs, and what reaching it from the core costs.
##
## Positions, parents and effects come from the real PerkTree.build(), so the
## editor draws the web the player will actually see - including the
## default_effects fallback, which is resolved by the time a PerkDef exists.
##
## Returns { "perks": [ {...}, ... ], "branches": [ {...}, ... ], "errors": [...] }
static func perks() -> Dictionary:
	var branch_list := load(PERK_BRANCHES_PATH) as PerkBranchList
	if branch_list == null:
		return {"perks": [], "branches": [], "errors": ["could not load " + PERK_BRANCHES_PATH]}

	var built := PerkTree.build(branch_list)
	var branches := {}      # key -> PerkBranchDef
	var authored := {}      # perk id -> res_path of the authored PerkNodeDef
	var own_effects := {}   # perk id -> true when it declares effects of its own
	_collect_authored(branch_list.core, authored, own_effects)
	for branch: PerkBranchDef in branch_list.branches:
		branches[branch.key] = branch
		for root: PerkNodeDef in branch.roots:
			_collect_authored(root, authored, own_effects)

	var by_id := {}
	var to_max := {}        # perk id -> BigNumber, cost of every level of that perk
	for perk: PerkDef in built:
		by_id[perk.id] = perk
		to_max[perk.id] = _cost_to_max(perk)

	var rows: Array = []
	for perk: PerkDef in built:
		# Ancestors kept apart from the perk's own cost: added to its first level
		# that sum is what reaching this perk costs before it has been levelled,
		# which is the cheap end of the web view's gradient.
		var ancestor_cost := BigNumber.new(0.0, 0)
		var depth := 0
		var walker: PerkDef = by_id.get(perk.parent_id)
		while walker != null:
			ancestor_cost = ancestor_cost.add(to_max[walker.id])
			depth += 1
			walker = by_id.get(walker.parent_id)
		var path_cost := ancestor_cost.add(to_max[perk.id])
		var first_level_cost := _level_cost(perk, 0)
		var last_level_cost := _level_cost(perk, perk.max_level - 1)
		var branch: PerkBranchDef = branches.get(perk.branch_key)
		var effect: UpgradeEffectDef = perk.effects[0] if not perk.effects.is_empty() else null
		var row := {
			"id": String(perk.id),
			"res_path": authored.get(perk.id, ""),
			"parent_id": String(perk.parent_id),
			"branch_key": String(perk.branch_key),
			"branch_label": branch.label if branch else "core",
			"hue": branch.hue if branch else 0.0,
			"display_name": perk.display_name,
			"world_x": perk.world_x,
			"world_y": perk.world_y,
			"depth": depth,
			"max_level": perk.max_level,
			"cost_growth": perk.cost_growth,
			"cost_growth_exponent": perk.cost_growth_exponent,
			"base_cost": _big_pair(perk.base_cost),
			"cost_to_max": _big_pair(to_max[perk.id]),
			"path_cost": _big_pair(path_cost),
			# The cheap end of each scale, so the web can draw a perk as the span
			# it really is - first level to last - instead of one number.
			"first_level_cost": _big_pair(first_level_cost),
			"last_level_cost": _big_pair(last_level_cost),
			"entry_cost": _big_pair(ancestor_cost.add(first_level_cost)),
		}
		if effect:
			row["stat"] = String(effect.stat)
			row["op"] = _enum_key(UpgradeEffectDef.Op, effect.op)
			row["per_level"] = effect.per_level
			row["effect_at_max"] = _big_pair(effect.magnitude(perk.max_level))
			row["effect_at_first"] = _big_pair(effect.magnitude(1))
		# Where the effects actually live, so the editor can open them without
		# walking the branch itself: either on the node or on its branch.
		var effect_paths: Array = []
		for resolved: UpgradeEffectDef in perk.effects:
			effect_paths.append(resolved.resource_path)
		row["effect_paths"] = effect_paths
		row["effects_inherited"] = not effect_paths.is_empty() and not own_effects.has(perk.id)
		rows.append(row)

	return {"perks": rows, "branches": _branch_rollup(rows), "errors": []}


## What buying the next level costs while sitting at `level`, charged through
## the same UpgradeSystem the game uses. Clamped to the perk's own range, so a
## perk with no levels prices at zero rather than off the end of its curve.
static func _level_cost(perk: PerkDef, level: int) -> BigNumber:
	if perk.max_level <= 0:
		return BigNumber.new(0.0, 0)
	var system := UpgradeSystem.new()
	system.register(perk)
	system.from_save({String(perk.id): clampi(level, 0, perk.max_level - 1)})
	return system.cost(perk.id)


## Every level of one perk added up: what maxing it costs from zero.
static func _cost_to_max(perk: PerkDef) -> BigNumber:
	if perk.max_level <= 0:
		return BigNumber.new(0.0, 0)
	var system := UpgradeSystem.new()
	system.register(perk)
	var total := BigNumber.new(0.0, 0)
	for level in range(perk.max_level):
		system.from_save({String(perk.id): level})
		total = total.add(system.cost(perk.id))
	return total


## id -> resource_path for the authored nodes, so a perk in the web view can be
## opened and edited. PerkDefs are generated and have no path of their own.
## `own_effects` records which nodes declare effects rather than running on their
## branch's, which is the difference between editing one perk and editing all of
## them.
static func _collect_authored(node: PerkNodeDef, out: Dictionary, own_effects: Dictionary) -> void:
	if node == null:
		return
	out[node.id] = node.resource_path
	if not node.effects.is_empty():
		own_effects[node.id] = true
	for child: PerkNodeDef in node.children:
		_collect_authored(child, out, own_effects)


## Per branch: how much it costs to max, how big it is, and what it adds up to
## per stat. Effects are bucketed by stat and op the same way UpgradeSystem does,
## because that is the only grouping in which two numbers are comparable.
static func _branch_rollup(rows: Array) -> Array:
	var by_key := {}
	var order: Array = []
	for row: Dictionary in rows:
		var key: String = row["branch_key"]
		if not by_key.has(key):
			by_key[key] = {
				"branch_key": key,
				"branch_label": row["branch_label"],
				"hue": row["hue"],
				"perk_count": 0,
				"max_depth": 0,
				"total_cost_to_max": BigNumber.new(0.0, 0),
				"deepest_path_cost": BigNumber.new(0.0, 0),
				"stats": {},
			}
			order.append(key)
		var entry: Dictionary = by_key[key]
		entry["perk_count"] += 1
		entry["max_depth"] = maxi(entry["max_depth"], row["depth"])
		entry["total_cost_to_max"] = entry["total_cost_to_max"].add(_big_from_pair(row["cost_to_max"]))
		var path_cost := _big_from_pair(row["path_cost"])
		if path_cost.gt(entry["deepest_path_cost"]):
			entry["deepest_path_cost"] = path_cost
		if row.has("stat"):
			var stat_key: String = "%s (%s)" % [row["stat"], row["op"]]
			var stats: Dictionary = entry["stats"]
			var total: BigNumber = stats.get(stat_key, BigNumber.new(0.0, 0))
			stats[stat_key] = total.add(_big_from_pair(row["effect_at_max"]))

	var out: Array = []
	for key: String in order:
		var entry: Dictionary = by_key[key]
		var stats := {}
		for stat_key: String in entry["stats"]:
			stats[stat_key] = _big_pair(entry["stats"][stat_key])
		entry["stats"] = stats
		entry["total_cost_to_max"] = _big_pair(entry["total_cost_to_max"])
		entry["deepest_path_cost"] = _big_pair(entry["deepest_path_cost"])
		out.append(entry)
	return out


static func _big_from_pair(pair: Array) -> BigNumber:
	return BigNumber.new(pair[0], pair[1])

#endregion


#region Create

## Adds a new sub-resource to an existing file and links it in one save.
##
## `request` is
##   { "in_file": "res://…tres",
##     "sub_id": "node_5",                       # optional, derived when absent
##     "values": { "column": "encoded value" },  # optional
##     "link": { "res_path": "…::node_3a", "column": "children", "index": 1 } }
##
## The link is mandatory. Godot drops a sub-resource nothing points at when the
## file is written, so creating one unlinked would silently produce nothing.
static func create(data_dir: String, request: Dictionary, dry_run: bool) -> Dictionary:
	if request.has("path"):
		return _create_file(data_dir, request, dry_run)

	var link: Dictionary = request.get("link", {})
	if link.is_empty():
		return _failed("'link' is required - an unreferenced sub-resource is dropped on save")

	var file_path: String = request.get("in_file", "")
	if not ResourceLoader.exists(file_path):
		return _failed("no such resource %s" % file_path)

	# Read the whole data set first: identity has to be unique across the table,
	# and snapshot() resets the open-file state this function then builds up.
	var existing: Dictionary = snapshot(data_dir).get("data", {})

	_open_files.clear()
	_subresources.clear()
	if _load_file(file_path) == null:
		return _failed("could not load %s" % file_path)

	var owner_path: String = link.get("res_path", file_path)
	var owner := _find_in_file(file_path, owner_path)
	if owner == null:
		return _failed("no sub-resource %s" % owner_path)

	var column := StringName(link.get("column", ""))
	if not _properties_by_name(owner).has(column):
		return _failed("%s has no property '%s'" % [owner_path, column])
	var list: Variant = owner.get(column)
	if typeof(list) != TYPE_ARRAY:
		return _failed("%s.%s is not a list" % [owner_path, column])

	# The array's element type says what to build, so the class is never guessed.
	var script: Script = (list as Array).get_typed_script()
	if script == null:
		return _failed("%s.%s has no element script to instantiate" % [owner_path, column])

	var res: Resource = script.new()
	var properties := _properties_by_name(res)
	var values: Dictionary = request.get("values", {})
	for name_text: String in values:
		var name := StringName(name_text)
		if not properties.has(name):
			return _failed("new %s has no property '%s'" % [_class_key(script), name])
		var decoded: Variant = decode_value(str(values[name_text]), properties[name], res.get(name))
		res.set(name, decoded)

	var table := _class_key(script)
	var clash := _identity_clash(existing.get(table, {}), res, properties)
	if not clash.is_empty():
		return _failed(clash)

	var sub_id: String = request.get("sub_id", "")
	if sub_id.is_empty():
		sub_id = _next_sub_id(file_path)
	var new_path := "%s::%s" % [file_path, sub_id]
	if _subresources.get(file_path, {}).has(new_path):
		return _failed("%s already exists" % new_path)
	res.resource_scene_unique_id = sub_id

	var array := list as Array
	var index := clampi(int(link.get("index", array.size())), 0, array.size())
	array.insert(index, res)
	owner.set(column, array)

	var changes: Array = ["created %s and linked it into %s.%s at index %d"
		% [new_path, owner_path, column, index]]
	if dry_run:
		return {"path": new_path, "changes": changes, "saved": 0, "errors": []}

	var errors: Array = []
	var original_text := FileAccess.get_file_as_string(file_path)
	var err := ResourceSaver.save(_open_files[file_path], file_path)
	if err != OK:
		return _failed("%s: save failed (%s)" % [file_path, error_string(err)])
	if not _restore_uids(file_path, original_text):
		errors.append("%s: could not restore uids after save" % file_path)
	return {"path": new_path, "changes": changes, "saved": 1, "errors": errors}


## Creates a standalone .tres.
##
## `request` is
##   { "table": "UpgradeEffectDef",
##     "path": "res://data/…/foo.tres",
##     "values": { … },
##     "link": { "res_path": …, "column": …, "index": … } }   # optional
##
## Unlike a sub-resource, a file survives on its own. Upgrades are found by a
## directory walk ([app.gd] _load_upgrade_defs), so a link is optional here. For
## every other class an unlinked file is never loaded, which the caller is told
## about rather than silently allowed.
static func _create_file(data_dir: String, request: Dictionary, dry_run: bool) -> Dictionary:
	var path: String = request.get("path", "")
	if not path.begins_with(data_dir):
		return _failed("%s is outside %s" % [path, data_dir])
	if not path.ends_with(".tres"):
		return _failed("%s must end in .tres" % path)
	if ResourceLoader.exists(path):
		return _failed("%s already exists" % path)

	var existing: Dictionary = snapshot(data_dir).get("data", {})
	var table_name: String = request.get("table", "")
	var script_path: String = existing.get(table_name, {}).get("script", "")
	if script_path.is_empty():
		return _failed("unknown table '%s' - no resource of that class exists to copy the script from"
			% table_name)
	var script: Script = load(script_path)
	if script == null:
		return _failed("could not load %s" % script_path)

	_open_files.clear()
	_subresources.clear()

	var res: Resource = script.new()
	var properties := _properties_by_name(res)
	var values: Dictionary = request.get("values", {})
	for name_text: String in values:
		var name := StringName(name_text)
		if not properties.has(name):
			return _failed("new %s has no property '%s'" % [table_name, name])
		res.set(name, decode_value(str(values[name_text]), properties[name], res.get(name)))

	var clash := _identity_clash(existing.get(table_name, {}), res, properties)
	if not clash.is_empty():
		return _failed(clash)

	var link: Dictionary = request.get("link", {})
	var changes: Array = ["created %s" % path]
	# Only the upgrade tree is found by a directory walk. Everything else must be
	# pointed at by something or the game never loads it.
	var orphan := link.is_empty() and table_name not in [
		"UpgradeDef", "UpgradeEffectDef", "ScalingSourceDef"]
	if dry_run:
		if not link.is_empty():
			changes.append("would link it into %s.%s" % [link.get("res_path"), link.get("column")])
		if orphan:
			changes.append("note: nothing would reference it, so the game will not load it")
		return {"path": path, "changes": changes, "saved": 0, "errors": []}

	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return _failed("could not create %s (%s)" % [directory, error_string(made)])

	# FLAG_CHANGE_PATH so the in-memory resource takes its new path. Without it
	# res.resource_path stays empty, and linking it into another file embeds a
	# second copy as a [sub_resource] instead of referencing the file written.
	var err := ResourceSaver.save(res, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		return _failed("%s: save failed (%s)" % [path, error_string(err)])
	if res.resource_path != path:
		res.take_over_path(path)

	# Outside the editor the saver can't mint a uid, so the file gets written
	# without one and every later uid:// reference to it dangles.
	var uid := ResourceUID.create_id()
	ResourceUID.add_id(uid, path)
	var uid_text := ResourceUID.id_to_text(uid)
	if not _write_header_uid(path, uid_text):
		return _failed("%s: saved but could not write its uid" % path)
	changes.append("assigned %s" % uid_text)

	var errors: Array = []
	if not link.is_empty():
		var linked := _link_resource(res, link, {path: uid_text})
		if not linked.get("ok", false):
			errors.append(linked.get("error", "link failed"))
		else:
			changes.append(linked.get("change", ""))
	elif orphan:
		changes.append("note: nothing references it yet, so the game will not load it")

	return {"path": path, "changes": changes, "saved": 1, "errors": errors}


## Inserts an already-saved resource into another resource's list or slot.
## A list of StringName (BiomeDef.upgrade_ids) takes the identity value, not the
## path, the same distinction the graph draws between key and path references.
static func _link_resource(res: Resource, link: Dictionary, extra_uids: Dictionary) -> Dictionary:
	var owner_path: String = link.get("res_path", "")
	var owner_file := owner_path.get_slice("::", 0)
	if _load_file(owner_file) == null:
		return {"ok": false, "error": "could not load %s" % owner_file}
	var owner := _find_in_file(owner_file, owner_path)
	if owner == null:
		return {"ok": false, "error": "no such resource %s" % owner_path}

	var column := StringName(link.get("column", ""))
	var properties := _properties_by_name(owner)
	if not properties.has(column):
		return {"ok": false, "error": "%s has no property '%s'" % [owner_path, column]}

	var current: Variant = owner.get(column)
	var description := ""
	if typeof(current) == TYPE_ARRAY:
		var array := current as Array
		var index := clampi(int(link.get("index", array.size())), 0, array.size())
		var entry: Variant = res
		if array.get_typed_builtin() == TYPE_STRING_NAME:
			entry = res.get(&"id") if properties_has(res, &"id") else res.get(&"key")
			if entry == null or String(entry).is_empty():
				return {"ok": false, "error": "%s.%s stores ids, but the new resource has none"
					% [owner_path, column]}
		array.insert(index, entry)
		owner.set(column, array)
		description = "linked into %s.%s at index %d" % [owner_path, column, index]
	elif properties[column].type == TYPE_OBJECT:
		owner.set(column, res)
		description = "set as %s.%s" % [owner_path, column]
	else:
		return {"ok": false, "error": "%s.%s cannot hold a resource" % [owner_path, column]}

	var original_text := FileAccess.get_file_as_string(owner_file)
	var err := ResourceSaver.save(_open_files[owner_file], owner_file)
	if err != OK:
		return {"ok": false, "error": "%s: save failed (%s)" % [owner_file, error_string(err)]}
	_restore_uids(owner_file, original_text, extra_uids)
	return {"ok": true, "change": description}


static func properties_has(res: Resource, name: StringName) -> bool:
	return _properties_by_name(res).has(name)


## Puts the uid into a freshly written file's `[gd_resource …]` line.
static func _write_header_uid(path: String, uid_text: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return false
	var lines := text.split("\n")
	if lines.size() == 0 or not lines[0].begins_with("[gd_resource"):
		return false
	if "uid=" in lines[0]:
		return true
	lines[0] = '%s uid="%s"]' % [lines[0].trim_suffix("]"), uid_text]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("\n".join(lines))
	file.close()
	return true


static func _failed(message: String) -> Dictionary:
	return {"path": "", "changes": [], "saved": 0, "errors": [message]}


## Ids double as runtime keys, and for perks as save keys, so a duplicate merges
## two perks' saved levels. Checked before anything is written.
static func _identity_clash(
		table: Dictionary,
		res: Resource,
		properties: Dictionary) -> String:
	if table.is_empty():
		return ""
	var header: Array = table.get("header", [])
	for name: StringName in [&"id", &"key"]:
		if not properties.has(name):
			continue
		var value := encode_value(res.get(name), properties[name])
		if value.is_empty():
			return "'%s' must be set - it is this resource's identity" % name
		var column := header.find(String(name))
		if column == -1:
			continue
		for row: Array in table.get("rows", []):
			if row[column] == value:
				return "%s '%s' is already used by %s" % [name, value, row[0]]
	return ""


## First free "node_N" in the file, so generated ids follow the existing shape.
## A number already used as a family prefix is skipped too: "node_3" alongside
## "node_3a"/"node_3b" is free but reads as a sibling of them.
static func _next_sub_id(file_path: String) -> String:
	var used: Array[String] = []
	for path: String in _subresources.get(file_path, {}):
		used.append(path.get_slice("::", 1))
	var n := 1
	while true:
		var candidate := "node_%d" % n
		var taken := false
		for id: String in used:
			if id.begins_with(candidate):
				taken = true
				break
		if not taken:
			return candidate
		n += 1
	return "node_%d" % n

#endregion


#region Delete

## Removes a resource and every reference to it.
##
## `request` is { "res_path": "res://…tres[::id]", "force": false }.
##
## Unlinking *is* the deletion for a sub-resource: Godot drops one that nothing
## points at when the file is written. That also means deleting a perk node
## takes its whole subtree with it, so anything that would be destroyed as a
## side effect is reported and refused unless `force` is set.
static func delete(data_dir: String, request: Dictionary, dry_run: bool) -> Dictionary:
	var target_path: String = request.get("res_path", "")
	var force: bool = request.get("force", false)
	var file_path := target_path.get_slice("::", 0)
	var is_sub := "::" in target_path

	if not ResourceLoader.exists(file_path):
		return _failed("no such resource %s" % file_path)

	_open_files.clear()
	_subresources.clear()
	for path: String in _collect_resource_paths(data_dir):
		_load_file(path)

	var target := _find_in_file(file_path, target_path)
	if target == null:
		return _failed("no such resource %s" % target_path)

	var reachable_before := _reachable_subresources(file_path)
	var referrers := _referrers(target)
	var changes: Array = []
	for referrer: Dictionary in referrers:
		changes.append("unlinked from %s.%s" % [referrer.res_path, referrer.column])

	var dirty: Dictionary[String, bool] = {}
	for referrer: Dictionary in referrers:
		_unlink(referrer, target)
		dirty[String(referrer.res_path).get_slice("::", 0)] = true

	# Whatever is no longer reachable from the file's root would be silently lost.
	var collateral: Array = []
	if is_sub:
		var reachable_after := _reachable_subresources(file_path)
		for path: String in reachable_before:
			if path != target_path and not reachable_after.has(path):
				collateral.append(path)

	var needs_force := not collateral.is_empty()
	for path: String in collateral:
		changes.append("would also destroy %s" % path)
	changes.append("deleted %s" % target_path)

	# A preview never fails, the caller needs to see the collateral to decide
	# whether to confirm it.
	if dry_run:
		return {"path": target_path, "changes": changes, "collateral": collateral,
			"needs_force": needs_force, "saved": 0, "errors": []}

	if needs_force and not force:
		return {
			"path": target_path,
			"changes": [],
			"collateral": collateral,
			"needs_force": true,
			"saved": 0,
			"errors": ["deleting %s would also destroy %d resource(s) that nothing else keeps: %s"
				% [target_path, collateral.size(), ", ".join(collateral)]],
		}

	var errors: Array = []
	var saved := 0
	for path: String in dirty:
		if path == file_path and not is_sub:
			continue                       # about to be deleted outright
		var original_text := FileAccess.get_file_as_string(path)
		var err := ResourceSaver.save(_open_files[path], path)
		if err != OK:
			errors.append("%s: save failed (%s)" % [path, error_string(err)])
			continue
		_restore_uids(path, original_text)
		saved += 1

	if not is_sub:
		var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
		if removed != OK:
			errors.append("could not remove %s (%s)" % [file_path, error_string(removed)])

	return {"path": target_path, "changes": changes, "collateral": collateral,
		"needs_force": needs_force, "saved": saved, "errors": errors}


## Every place `target` is pointed at, as { res_path, column, kind }.
## `kind` is "object" for a direct reference and "key" for one stored as the
## target's id, since BiomeDef.upgrade_ids holds ids, not paths.
static func _referrers(target: Resource) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var identity := ""
	var target_properties := _properties_by_name(target)
	for name: StringName in [&"id", &"key"]:
		if target_properties.has(name):
			identity = encode_value(target.get(name), target_properties[name])
			break

	for file_path: String in _subresources:
		for holder_path: String in _subresources[file_path]:
			var holder: Resource = _subresources[file_path][holder_path]
			if holder == target:
				continue
			for column: Dictionary in _exportable_properties(holder):
				var value: Variant = holder.get(column.name)
				var entry := {"res_path": holder_path, "column": column.name}
				match typeof(value):
					TYPE_OBJECT:
						if value == target:
							found.append(entry.merged({"kind": "object"}, true))
					TYPE_ARRAY:
						var array := value as Array
						# `has` on a typed array validates what it is handed and
						# logs an error when the types cannot match, so the type
						# is checked here rather than by trying and failing.
						if _may_hold(array, target) and array.has(target):
							found.append(entry.merged({"kind": "object"}, true))
						elif not identity.is_empty() and array.get_typed_builtin() == TYPE_STRING_NAME \
								and array.has(StringName(identity)):
							found.append(entry.merged({"kind": "key"}, true))
					TYPE_DICTIONARY:
						for key: Variant in value:
							if value[key] == target:
								found.append(entry.merged({"kind": "dict", "dict_key": key}, true))
	return found


## True when `array` could hold `target` at all: untyped, or typed to the class
## the target is. Anything else can be skipped without looking inside it.
static func _may_hold(array: Array, target: Resource) -> bool:
	var builtin := array.get_typed_builtin()
	if builtin != TYPE_NIL and builtin != TYPE_OBJECT:
		return false
	var element_script: Variant = array.get_typed_script()
	return element_script == null or element_script == target.get_script()


static func _unlink(referrer: Dictionary, target: Resource) -> void:
	var holder := _find_in_file(String(referrer.res_path).get_slice("::", 0),
		String(referrer.res_path))
	if holder == null:
		return
	var column := StringName(referrer.column)
	var value: Variant = holder.get(column)
	match referrer.kind:
		"object":
			if typeof(value) == TYPE_ARRAY:
				var array := value as Array
				array.erase(target)
				holder.set(column, array)
			else:
				holder.set(column, null)
		"key":
			var array := value as Array
			var properties := _properties_by_name(target)
			for name: StringName in [&"id", &"key"]:
				if properties.has(name):
					array.erase(StringName(encode_value(target.get(name), properties[name])))
					break
			holder.set(column, array)
		"dict":
			var dict := value as Dictionary
			dict.erase(referrer.dict_key)
			holder.set(column, dict)


## Sub-resource paths still reachable from the file's root, i.e. the ones a save
## would write out.
static func _reachable_subresources(file_path: String) -> Dictionary:
	var root: Resource = _open_files.get(file_path)
	if root == null:
		return {}
	var found: Array[Resource] = []
	var seen: Dictionary[int, bool] = {}
	_expand_subresources(root, file_path, found, seen)
	var paths := {}
	for res: Resource in found:
		if "::" in res.resource_path:
			paths[res.resource_path] = true
	return paths

#endregion


#region Unused

## Read for res:// paths and uids, so a resource the game loads by path counts as
## used even though no other resource points at it. Reports are deliberately not
## in here: tools/balance_report.json names every perk file it sampled, and
## reading it back would keep the whole prestige web alive by accident.
const SOURCE_SUFFIXES: Array[String] = [".gd", ".tscn", ".cfg", ".godot"]

## Left out of that search. Addons are third-party code that never names game
## data, and the tools here are the editor rather than the game: they talk about
## res://data in whole folders and prefix tests, which would keep every file
## under them alive no matter what the game actually loads.
const SOURCE_SKIPPED: Array[String] = ["res://addons", "res://reports", "res://tools"]

## Everything under `data_dir` that nothing keeps alive: no other resource points
## at it, and no script, scene or project file names its path or its uid.
##
## Both halves matter. A branch effect dropped from its last node is unreachable
## but still on disk, and so is a whole upgrade file; meanwhile the registries the
## game loads by path - all_branches.tres and friends - have no referrer either,
## and deleting one of those would take the game with it.
##
## Sub-resources cannot show up here: they are indexed by walking down from their
## file's root, so anything listed is reachable, and reachable means referenced.
##
## Returns { "unused": [ { "res_path", "type", "label", "in_source": false }, … ],
##           "checked": int, "kept_by_source": [...], "errors": [...] }
static func unused(data_dir: String) -> Dictionary:
	var errors: Array = []
	_open_files.clear()
	_subresources.clear()

	var paths := _collect_resource_paths(data_dir)
	for path: String in paths:
		if _load_file(path) == null:
			errors.append("could not load %s" % path)

	var in_source := _paths_named_in_source(paths, data_dir)
	var rows: Array = []
	var kept_by_source: Array = []
	for path: String in paths:
		var res: Resource = _open_files.get(path)
		if res == null:
			continue
		if in_source.has(path):
			kept_by_source.append(path)
			continue
		if not _referrers(res).is_empty():
			continue
		var script: Script = res.get_script()
		rows.append({
			"res_path": path,
			"type": _class_key(script) if script != null else "Resource",
			"label": _display_label(res),
		})

	return {"unused": rows, "checked": paths.size(), "kept_by_source": kept_by_source,
		"errors": errors}


## Of `paths`, the ones a script, scene or project file names - by res:// path,
## by uid (a scene stores both, and either one keeps the file in the game), or by
## the directory they sit in: UpgradeDefLoader loads whole folders, so naming
## "res://data/upgrades/symbiosis/" keeps every def inside it.
static func _paths_named_in_source(paths: Array[String], data_dir: String) -> Dictionary:
	# "res://data" itself is not a claim on anything: this file names it as the
	# default the editor scans, and so does the CLI. Only a folder below it says
	# something about what the game loads.
	var data_root := data_dir.trim_suffix("/") + "/"
	var by_uid := {}
	for path: String in paths:
		var id := ResourceLoader.get_resource_uid(path)
		if id != ResourceUID.INVALID_ID:
			by_uid[ResourceUID.id_to_text(id)] = path

	var sources: Array[String] = []
	for suffix: String in SOURCE_SUFFIXES:
		_walk_source("res://", suffix, sources)

	# Every res:// string in the source, split into the files it names outright
	# and the folders whose whole contents it claims.
	var named := {}
	var folders: Array[String] = []
	var path_finder := RegEx.create_from_string("res://[A-Za-z0-9_./-]*")
	var uid_finder := RegEx.create_from_string("uid://[a-z0-9]+")
	var out := {}
	for source: String in sources:
		var text := FileAccess.get_file_as_string(source)
		if text.is_empty():
			continue
		for found: RegExMatch in path_finder.search_all(text):
			var token := found.get_string()
			if not token.ends_with("/") and not DirAccess.dir_exists_absolute(token):
				named[token] = true
				continue
			var folder := token if token.ends_with("/") else token + "/"
			if folder != data_root and folder.begins_with(data_root):
				folders.append(folder)
		for found: RegExMatch in uid_finder.search_all(text):
			var target: String = by_uid.get(found.get_string(), "")
			if not target.is_empty():
				out[target] = true

	for path: String in paths:
		if named.has(path):
			out[path] = true
			continue
		for folder: String in folders:
			if path.begins_with(folder):
				out[path] = true
				break
	return out


## Like _walk, minus the directories whose contents say nothing about what the
## game loads. Kept separate so the plain walk stays a plain walk.
static func _walk_source(dir_path: String, suffix: String, out: Array[String]) -> void:
	if SOURCE_SKIPPED.has(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_walk_source(full, suffix, out)
		elif entry.ends_with(suffix):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


## The most human name a resource carries, for a list the user reads rather than
## a table keyed by path. Same order of preference the editor's own labels use.
static func _display_label(res: Resource) -> String:
	var properties := _properties_by_name(res)
	for name: StringName in [&"display_name", &"label", &"name", &"key", &"id"]:
		if properties.has(name):
			var value := String(res.get(name))
			if not value.is_empty():
				return value
	return res.resource_path.get_file()

#endregion


#region Apply

## `patch` is { "res://file.tres::id": { "column": "encoded value", … }, … },
## using the same encoding `snapshot()` produces. Columns that already hold the
## given value are skipped, so a patch can safely repeat unchanged fields.
static func apply(patch: Dictionary, dry_run: bool) -> Dictionary:
	var changes: Array = []
	var errors: Array = []
	var dirty_files: Dictionary[String, bool] = {}
	_open_files.clear()
	_subresources.clear()

	for res_path: String in patch:
		var file_path := res_path.get_slice("::", 0)
		if not ResourceLoader.exists(file_path):
			errors.append("no such resource %s" % file_path)
			continue
		# Same instance the editor holds, so a write can't be undone by the editor
		# later flushing its own stale copy of the resource.
		if _load_file(file_path) == null:
			errors.append("could not load %s" % file_path)
			continue
		var res := _find_in_file(file_path, res_path)
		if res == null:
			errors.append("no sub-resource %s" % res_path)
			continue

		var properties := _properties_by_name(res)
		var values: Dictionary = patch[res_path]
		for name_text: String in values:
			var name := StringName(name_text)
			if not properties.has(name):
				errors.append("%s has no property '%s'" % [res_path, name])
				continue
			var column: Dictionary = properties[name]
			var text := str(values[name_text])
			var old_value: Variant = res.get(name)
			# Captured before decoding: arrays and dictionaries are mutated in place,
			# so re-encoding old_value afterwards would show the new value.
			var old_text := encode_value(old_value, column)
			if old_text == text:
				continue
			var decoded: Variant = decode_value(text, column, old_value)
			if decoded == null and column.type != TYPE_NIL and column.type != TYPE_OBJECT:
				errors.append("%s.%s - cannot parse '%s'" % [res_path, name, text])
				continue
			res.set(name, decoded)
			changes.append("%s.%s: %s -> %s" % [res_path, name, old_text, text])
			dirty_files[file_path] = true

	var saved := 0
	for file_path: String in dirty_files:
		if dry_run:
			saved += 1
			continue
		var original_text := FileAccess.get_file_as_string(file_path)
		var err := ResourceSaver.save(_open_files[file_path], file_path)
		if err != OK:
			errors.append("%s: save failed (%s)" % [file_path, error_string(err)])
			continue
		if not _restore_uids(file_path, original_text):
			errors.append("%s: could not restore uids after save" % file_path)
		saved += 1

	return {"changes": changes, "saved": saved, "errors": errors}

#endregion


## What kind of editor a column deserves, taken from the property itself rather
## than guessed from the text. Enums carry their names in declaration order.
static func _column_meta(column: Dictionary) -> Dictionary:
	var meta := {"name": column.name}
	if column.hint == PROPERTY_HINT_ENUM:
		meta["type"] = "enum"
		meta["options"] = _enum_entries(column.hint_string).keys()
		return meta

	match column.type:
		TYPE_BOOL:
			meta["type"] = "bool"
		TYPE_INT:
			meta["type"] = "int"
		TYPE_FLOAT:
			meta["type"] = "float"
		TYPE_COLOR:
			meta["type"] = "color"
		TYPE_OBJECT:
			meta["type"] = "resource"
		TYPE_ARRAY:
			meta["type"] = "array"
		TYPE_DICTIONARY:
			meta["type"] = "dictionary"
		TYPE_STRING, TYPE_STRING_NAME:
			meta["type"] = "multiline" if column.hint == PROPERTY_HINT_MULTILINE_TEXT else "text"
		_:
			meta["type"] = "text"
	return meta


#region Value codec

## Encodes a property value as a single text field. Enums become their names,
## resources their `res://` paths, arrays a `|`-separated list.
static func encode_value(value: Variant, column: Dictionary) -> String:
	if column.hint == PROPERTY_HINT_ENUM and typeof(value) == TYPE_INT:
		var name := _enum_name(column.hint_string, value)
		if not name.is_empty():
			return name

	match typeof(value):
		TYPE_NIL:
			return ""
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_COLOR:
			return "#%s" % (value as Color).to_html(true)
		TYPE_OBJECT:
			var res := value as Resource
			return "" if res == null else res.resource_path
		TYPE_DICTIONARY:
			# Plain str() on a Dictionary holding Resources yields
			# "(res://x.tres):<Resource#-92233…>", which is neither readable nor
			# loadable. Encode entries the same way single values are encoded.
			var key_enum := _dict_key_enum(column)
			var plain := {}
			for key: Variant in value:
				var key_text := str(key)
				if not key_enum.is_empty() and typeof(key) == TYPE_INT:
					var name := _enum_name(key_enum, key)
					if not name.is_empty():
						key_text = name
				plain[key_text] = encode_value(value[key], {
					"type": typeof(value[key]), "hint": PROPERTY_HINT_NONE, "hint_string": ""})
			return JSON.stringify(plain)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var parts := PackedStringArray()
			for element: Variant in value:
				parts.append(encode_value(element, {"type": typeof(element), "hint": PROPERTY_HINT_NONE, "hint_string": ""}))
			return LIST_SEPARATOR.join(parts)
		_:
			return str(value)


## Decodes a text field back into a property value. `current` is the value
## already on the resource. Arrays are mutated in place so a typed array keeps
## its element type.
static func decode_value(text: String, column: Dictionary, current: Variant) -> Variant:
	if column.hint == PROPERTY_HINT_ENUM:
		var value: Variant = _enum_value(column.hint_string, text)
		if value != null:
			return value

	match column.type:
		TYPE_BOOL:
			return text.strip_edges().to_lower() in ["true", "1", "yes"]
		TYPE_INT:
			return int(text.strip_edges().to_float())
		TYPE_FLOAT:
			return text.strip_edges().to_float()
		TYPE_STRING:
			return text
		TYPE_STRING_NAME:
			return StringName(text)
		TYPE_COLOR:
			return Color.html(text.strip_edges())
		TYPE_OBJECT:
			var path := text.strip_edges()
			return null if path.is_empty() else _load_ref(path)
		TYPE_DICTIONARY:
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) != TYPE_DICTIONARY:
				return current
			# Mutated in place, like arrays, so a typed Dictionary keeps its typing.
			var dict: Dictionary = current if typeof(current) == TYPE_DICTIONARY else {}
			var key_enum := _dict_key_enum(column)
			var key_builtin := dict.get_typed_key_builtin() if dict.is_typed_key() else TYPE_NIL
			dict.clear()
			for key: String in parsed:
				dict[_decode_dict_key(key, key_enum, key_builtin)] = _decode_dict_value(
					str(parsed[key]))
			return dict
		TYPE_ARRAY:
			var array: Array = current if typeof(current) == TYPE_ARRAY else []
			array.clear()
			for part: String in _split_list(text):
				array.append(_load_ref(part) if part.begins_with("res://") else part)
			return array
		_:
			return text

#endregion


#region Helpers

static func _split_list(text: String) -> PackedStringArray:
	var parts := PackedStringArray()
	for raw: String in text.split(LIST_SEPARATOR):
		var part := raw.strip_edges()
		if not part.is_empty():
			parts.append(part)
	return parts


## `hint_string` is either "A,B,C" or "A:0,B:1,C:4" when the enum has explicit
## values. `ScalingSourceDef.Kind` skips ordinals, so both forms occur.
static func _enum_entries(hint_string: String) -> Dictionary[String, int]:
	var entries: Dictionary[String, int] = {}
	var next := 0
	for raw: String in hint_string.split(",", false):
		var entry := raw.strip_edges()
		if entry.is_empty():
			continue
		var colon := entry.rfind(":")
		if colon == -1:
			entries[entry] = next
			next += 1
		else:
			var value := int(entry.substr(colon + 1))
			entries[entry.substr(0, colon)] = value
			next = value + 1
	return entries


static func _enum_name(hint_string: String, value: int) -> String:
	var entries := _enum_entries(hint_string)
	for name: String in entries:
		if entries[name] == value:
			return name
	return ""


## Accepts the exported label ("Node Count"), the GDScript identifier
## ("NODE_COUNT") or the raw ordinal, so a spreadsheet edit doesn't have to
## reproduce Godot's capitalisation.
static func _enum_value(hint_string: String, text: String) -> Variant:
	var entries := _enum_entries(hint_string)
	var key := text.strip_edges()
	if entries.has(key):
		return entries[key]
	var normalised := _normalise_enum_key(key)
	for name: String in entries:
		if _normalise_enum_key(name) == normalised:
			return entries[name]
	if key.is_valid_int():
		return int(key)
	return null


## A typed Dictionary packs both halves into one hint as
## "<type>/<hint>:<hint_string>;<type>/<hint>:<hint_string>". Returns the key
## half's enum spec when the keys are an enum, so they can be written by name.
static func _dict_key_enum(column: Dictionary) -> String:
	if column.hint != PROPERTY_HINT_TYPE_STRING:
		return ""
	var halves := String(column.hint_string).split(";")
	if halves.is_empty():
		return ""
	var key_spec := halves[0]
	var colon := key_spec.find(":")
	if colon == -1 or not key_spec.substr(0, colon).ends_with("/%d" % PROPERTY_HINT_ENUM):
		return ""
	return key_spec.substr(colon + 1)


static func _decode_dict_key(key: String, key_enum: String, key_builtin: int) -> Variant:
	if not key_enum.is_empty():
		var value: Variant = _enum_value(key_enum, key)
		if value != null:
			return value
	match key_builtin:
		TYPE_INT:         return int(key)
		TYPE_FLOAT:       return key.to_float()
		TYPE_STRING_NAME: return StringName(key)
		_:                return key


static func _decode_dict_value(text: String) -> Variant:
	return _load_ref(text) if text.begins_with("res://") else text


static func _load_file(file_path: String) -> Resource:
	if not _open_files.has(file_path):
		var res := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			return null
		_open_files[file_path] = res
		# Indexed before anything is written. Decoding a reference list clears the
		# array it is about to rebuild, so a node reachable only through that
		# array would vanish from the object graph mid-import.
		var found: Array[Resource] = []
		var seen: Dictionary[int, bool] = {}
		_expand_subresources(res, file_path, found, seen)
		var index: Dictionary[String, Resource] = {}
		for sub: Resource in found:
			index[sub.resource_path] = sub
		_subresources[file_path] = index
	return _open_files[file_path]


## The resource a "file.tres::id" path names, or the file itself when it has no
## "::" part. Reads the index, never the live object graph.
static func _find_in_file(file_path: String, res_path: String) -> Resource:
	var parent := _load_file(file_path)
	if parent == null or not "::" in res_path:
		return parent
	var index: Dictionary = _subresources.get(file_path, {})
	return index.get(res_path)


## Resolves a reference written in a CSV back to a resource.
##
## A sub-resource path ("file.tres::node_4a") cannot go through ResourceLoader:
## it returns null unless that sub-resource is already cached, which turns an
## edited child list into `Array[…]([null, …])`. Sub-resources resolve through
## the file that owns them, which is also the instance this import is editing, so
## a node moved between parents keeps its identity instead of being duplicated.
static func _load_ref(path: String) -> Resource:
	if not "::" in path:
		return ResourceLoader.load(path)
	return _find_in_file(path.get_slice("::", 0), path)


static func _normalise_enum_key(text: String) -> String:
	return text.to_lower().replace("_", "").replace(" ", "")


## Puts back the `uid="uid://…"` attributes that a headless save drops.
##
## `ResourceSaver` resolves a path to its uid through a hook only the editor
## installs, so outside it every `[gd_resource]` and `[ext_resource]` line is
## written without one. The registries under res://data key their entries by uid,
## so losing them breaks lookups. Only lines that carried a uid before the save
## get one back, keeping the diff to the changed fields. A no-op in the editor.
static func _restore_uids(
		file_path: String,
		original_text: String,
		extra_uids: Dictionary = {}) -> bool:
	if original_text.is_empty():
		return false
	var saved_text := FileAccess.get_file_as_string(file_path)
	if saved_text.is_empty():
		return false

	var path_re := RegEx.create_from_string('path="([^"]*)"')
	var uid_re := RegEx.create_from_string('uid="([^"]*)"')
	# Seeded with the uids of files this save is the first to reference, which
	# have no line in the original text to copy from.
	var uid_by_path: Dictionary[String, String] = {}
	for path: String in extra_uids:
		uid_by_path[path] = str(extra_uids[path])
	var header_uid := ""

	for line: String in original_text.split("\n"):
		var uid_match := uid_re.search(line)
		if uid_match == null:
			continue
		if line.begins_with("[gd_resource"):
			header_uid = uid_match.get_string(1)
		elif line.begins_with("[ext_resource"):
			var path_match := path_re.search(line)
			if path_match != null:
				uid_by_path[path_match.get_string(1)] = uid_match.get_string(1)

	var lines := saved_text.split("\n")
	for i: int in lines.size():
		var line: String = lines[i]
		if "uid=" in line:
			continue
		if line.begins_with("[gd_resource") and not header_uid.is_empty():
			lines[i] = '%s uid="%s"]' % [line.trim_suffix("]"), header_uid]
		elif line.begins_with("[ext_resource"):
			var path_match := path_re.search(line)
			if path_match != null and uid_by_path.has(path_match.get_string(1)):
				lines[i] = line.replace(
					'path="', 'uid="%s" path="' % uid_by_path[path_match.get_string(1)])

	var patched := "\n".join(lines)
	if patched == saved_text:
		return true
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(patched)
	file.close()
	return true


## Appends `res` and every resource stored *inside* the same file (Godot's
## `[sub_resource]` blocks, addressed as "file.tres::id") to `out`. Resources in
## other files are skipped, the directory walk reaches them on their own.
static func _expand_subresources(
		res: Resource,
		file_path: String,
		out: Array[Resource],
		seen: Dictionary[int, bool]) -> void:
	if res == null or seen.has(res.get_instance_id()):
		return
	seen[res.get_instance_id()] = true
	out.append(res)

	var internal_prefix := "%s::" % file_path
	for column: Dictionary in _exportable_properties(res):
		var value: Variant = res.get(column.name)
		var candidates: Array = value if typeof(value) == TYPE_ARRAY else [value]
		for candidate: Variant in candidates:
			if typeof(candidate) != TYPE_OBJECT:
				continue
			var child := candidate as Resource
			if child != null and child.resource_path.begins_with(internal_prefix):
				_expand_subresources(child, file_path, out, seen)



static func _exportable_properties(res: Resource) -> Array[Dictionary]:
	var columns: Array[Dictionary] = []
	for property: Dictionary in res.get_property_list():
		var usage: int = property.usage
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE \
				and usage & PROPERTY_USAGE_EDITOR \
				and usage & PROPERTY_USAGE_STORAGE:
			columns.append(property)
	return columns


static func _properties_by_name(res: Resource) -> Dictionary[StringName, Dictionary]:
	var by_name: Dictionary[StringName, Dictionary] = {}
	for property: Dictionary in _exportable_properties(res):
		by_name[StringName(property.name)] = property
	return by_name


static func _class_key(script: Script) -> String:
	var global_name := script.get_global_name()
	if not String(global_name).is_empty():
		return String(global_name)
	return script.resource_path.get_file().get_basename()


static func _collect_resource_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	_walk(dir_path, ".tres", paths)
	paths.sort()
	return paths



static func _walk(dir_path: String, suffix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_walk(full, suffix, out)
		elif entry.ends_with(suffix):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

#endregion
