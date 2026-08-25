class_name StatisticsViewModel
extends ViewModel
## VIEWMODEL: the statistics overlay - personal records, the milestone timeline,
## the prestige-run comparison and the bonus breakdown, all as rows a view can
## spawn without knowing what any of them are made of.
## References the model, never a Node.
##
## Built once in App._ready() and owned for the app's lifetime, mirroring
## App.achievements_vm.
##
## Everything here is read-only and rebuilt on read. The three cheap tabs cost a
## walk over a handful of arrays; `bonus_groups` costs a walk over every levelled
## upgrade in all eight tracks, which is why it is cached behind refresh_bonuses()
## rather than recomputed whenever a view repaints. See UpgradeSystem.breakdown().

const PROP_RECORDS := &"records_rows"
const PROP_MILESTONES := &"milestone_rows"
const PROP_RUNS := &"run_rows"
const PROP_BONUSES := &"bonus_groups"

## Peak keys paired with the label the records tab prints, in reading order. The
## BigNumber records first, the counts after them - the table is one list to the
## player, but the two halves format differently.
const _PEAK_LABELS := [
	[&"nutrients", "Most nutrients held"],
	[&"production", "Best production per tick"],
	[&"biomass", "Most biomass held"],
	[&"water", "Most water held"],
	[&"crystals", "Most crystals held"],
	[&"fertilizer", "Most fertilizer held"],
	[&"relics", "Most relics held"],
	[&"ichor", "Most ichor held"],
	[&"glyphs", "Most glyphs held"],
]
const _COUNT_LABELS := [
	[&"tick_count", "Longest run (ticks)"],
	[&"manual_nodes", "Most nodes grown"],
	[&"biomes_unlocked", "Most biomes open at once"],
	[&"biome_size", "Most biome size bought"],
	[&"player_level", "Highest player level"],
	[&"symbiosis_levels", "Most symbiosis levels"],
	[&"perk_levels", "Most perk levels"],
	[&"daily_streak", "Longest daily streak"],
]

## Built on demand and kept until something invalidates it. Null means "not built
## yet", which is not the same as an empty breakdown on a fresh save.
var _bonus_cache: Variant = null

# --- Read-only display properties bound by the View ---

## {label, value} rows. The lifetime totals sit alongside the peaks: "most held"
## and "earned in total" answer different questions and a player reading a
## records tab wants both.
var records_rows: Array[Dictionary]:
	get:
		var stats := App.stats_data
		var player := App.player_data
		var rows: Array[Dictionary] = []
		rows.append({"label": "Playing since", "value": TimeFormat.stamp(stats.first_played_at)})
		rows.append({"label": "Current run", "value": _current_run_duration()})
		for pair: Array in _PEAK_LABELS:
			rows.append({"label": pair[1], "value": stats.peak(pair[0]).to_display()})
		for pair: Array in _COUNT_LABELS:
			rows.append({"label": pair[1], "value": "%d" % stats.count(pair[0])})
		rows.append({"label": "Lifetime nutrients", "value": player.lifetime_nutrients.to_display()})
		rows.append({"label": "Lifetime crystals", "value": player.lifetime_crystals.to_display()})
		rows.append({"label": "Lifetime ticks", "value": "%d" % player.lifetime_ticks})
		rows.append({"label": "Nodes bought, ever", "value": "%d" % player.lifetime_manual_nodes})
		rows.append({"label": "Biome size bought, ever", "value": "%d" % player.lifetime_biome_size})
		rows.append({"label": "Events resolved", "value": "%d" % player.events_resolved})
		rows.append({"label": "Sporations", "value": "%d" % player.prestige_count})
		return rows

## {title, detail, when} rows, newest first - a timeline is read from the end a
## player was last at.
var milestone_rows: Array[Dictionary]:
	get:
		var rows: Array[Dictionary] = []
		var milestones: Array = App.stats_data.milestones
		for i in range(milestones.size() - 1, -1, -1):
			var row: Dictionary = milestones[i]
			var titled := _milestone_title(row)
			rows.append({
				"title": titled[0],
				"detail": titled[1],
				"when": TimeFormat.stamp(float(row.get("at", 0.0))),
			})
		return rows

## The run in progress first, then every finished run newest-first. Each row
## carries the same field list, so the view can lay them out as one comparison
## without asking which kind of row it has.
var run_rows: Array[Dictionary]:
	get:
		var rows: Array[Dictionary] = [_current_run_row()]
		var runs: Array = App.stats_data.runs
		for i in range(runs.size() - 1, -1, -1):
			rows.append(_finished_run_row(runs[i]))
		return rows

## Resource -> track -> upgrade, with the magnitudes formatted. Cached; see
## refresh_bonuses().
var bonus_groups: Array:
	get:
		if _bonus_cache == null:
			_bonus_cache = _build_bonus_groups()
		return _bonus_cache

# --- Commands (called by the View on input) ---

## Drops the cached breakdown so the next read rebuilds it. Called when the tab
## is opened, which is the only moment the cost is worth paying.
func refresh_bonuses() -> void:
	_bonus_cache = null
	_notify(PROP_BONUSES)

# --- Lifecycle ---

func _init() -> void:
	App.player_data.prestige_count_changed.connect(_on_run_changed)

func dispose() -> void:
	App.player_data.prestige_count_changed.disconnect(_on_run_changed)

# --- Model -> notification plumbing ---

func _on_run_changed(_value: int) -> void:
	_bonus_cache = null
	_notify(PROP_RECORDS)
	_notify(PROP_MILESTONES)
	_notify(PROP_RUNS)
	_notify(PROP_BONUSES)

# --- Row building ---

func _current_run_duration() -> String:
	var started := App.stats_data.run_started_at
	if started <= 0.0:
		return "-"
	return TimeFormat.duration(Time.get_unix_time_from_system() - started)

## The live run in the same shape a finished one has, so the two sit in one list.
## Built from current state rather than from StatsData, which has nothing about a
## run until it ends.
func _current_run_row() -> Dictionary:
	var player := App.player_data
	return {
		"title": "Run %d (in progress)" % [player.prestige_count + 1],
		"when": TimeFormat.stamp(App.stats_data.run_started_at),
		"in_progress": true,
		"fields": [
			{"label": "Played", "value": _current_run_duration()},
			{"label": "Ticks", "value": "%d" % player.tick_count},
			{"label": "Nutrients", "value": player.nutrients.to_display()},
			{"label": "Biomass so far", "value": App.prestige_system.preview_biomass_gain().to_display()},
			{"label": "Production/tick", "value": App.total_production().to_display()},
			{"label": "Nodes", "value": "%d" % App.stats_data.count(&"manual_nodes")},
			{"label": "Perk levels", "value": "%d" % App.prestige_upgrade_system.total_levels()},
			{"label": "Symbiosis levels", "value": "%d" % App.upgrade_system.total_levels()},
		],
	}

func _finished_run_row(record: Dictionary) -> Dictionary:
	var started := float(record.get("started_at", 0.0))
	var ended := float(record.get("ended_at", 0.0))
	var played := "-" if started <= 0.0 or ended <= 0.0 else TimeFormat.duration(ended - started)
	var deepest: String = record.get("deepest_biome", "")
	return {
		"title": "Run %d" % [int(record.get("index", 0))],
		"when": TimeFormat.stamp(ended),
		"in_progress": false,
		"fields": [
			{"label": "Played", "value": played},
			{"label": "Ticks", "value": "%d" % int(record.get("ticks", 0))},
			{"label": "Nutrients", "value": _saved_number(record, "nutrients")},
			{"label": "Biomass gained", "value": _saved_number(record, "biomass_gained")},
			{"label": "Production/tick", "value": _saved_number(record, "peak_production")},
			{"label": "Nodes", "value": "%d" % int(record.get("manual_nodes", 0))},
			{"label": "Perk levels", "value": "%d" % int(record.get("perk_levels", 0))},
			{"label": "Symbiosis levels", "value": "%d" % int(record.get("symbiosis_levels", 0))},
			{"label": "Deepest biome", "value": deepest if not deepest.is_empty() else "-"},
		],
	}

func _saved_number(record: Dictionary, key: String) -> String:
	return BigNumber.from_save(record.get(key, {})).to_display()

## [title, detail] for one milestone. Ids are turned back into display names here
## rather than stored in the save: a renamed biome should read by its new name.
func _milestone_title(row: Dictionary) -> Array:
	var key: String = row.get("key", "")
	var run := int(row.get("run", 0))
	match String(row.get("kind", "")):
		StatsSystem.MILESTONE_BIOME:
			return ["Reached %s" % _biome_name(key), "First unlocked during run %d" % [run + 1]]
		StatsSystem.MILESTONE_NODE:
			return ["Grew %s" % _node_name(key), "First bought during run %d" % [run + 1]]
		StatsSystem.MILESTONE_PRESTIGE:
			return ["Sporated (run %s)" % key, "Traded the run in for biomass"]
		_:
			return [key, ""]

func _biome_name(key: String) -> String:
	for def in App.biomes.biomes:
		if String(def.key) == key:
			return def.display_name
	return key

func _node_name(node_id: String) -> String:
	for node in App.nodes.mycelium_nodes:
		if str(node.node_id) == node_id:
			return node.name
	return "node %s" % node_id

## The model's groups with every number turned into the string a row prints.
## Formatting lives here rather than in BonusBreakdown so the model stays
## comparable and the view stays free of BigNumber.
func _build_bonus_groups() -> Array:
	var out: Array = []
	for group: Dictionary in BonusBreakdown.build(App.production_system):
		var sources: Array = []
		for source: Dictionary in group["sources"]:
			var upgrades: Array = []
			for upgrade: Dictionary in source["upgrades"]:
				var scope := _shared_scope(upgrade["effects"])
				var effects: Array = []
				for effect: Dictionary in upgrade["effects"]:
					effects.append(_effect_text(effect, scope.is_empty()))
				var display_name := String(upgrade["name"])
				if display_name.is_empty():
					display_name = String(upgrade["id"])
				upgrades.append({
					"name": display_name if scope.is_empty() else "%s - %s" % [display_name, scope],
					"level": "Lv %d" % int(upgrade["level"]),
					"effects": effects,
				})
			sources.append({"track": _track_name(source["track"]), "upgrades": upgrades})
		out.append({
			"resource": String(group["resource"]).capitalize(),
			"total": "global x%s" % (group["global_total"] as BigNumber).to_display(2),
			"count": "%d upgrade%s" % [group["upgrade_count"],
				"" if group["upgrade_count"] == 1 else "s"],
			"sources": sources,
		})
	return out

## The scope every one of an upgrade's effects shares, or "" when they differ or
## are global.
##
## Ten node-scoped copies of one upgrade are ten separate defs with one display
## name between them, so a column of "Mycelium Potency" repeated ten times is
## what a reader gets otherwise. Where the scope is the only thing telling them
## apart, it belongs in the name.
func _shared_scope(effects: Array) -> String:
	var shared := ""
	for effect: Dictionary in effects:
		var scope := _scope_name(String(effect["key"]))
		if scope.is_empty():
			return ""
		if shared.is_empty():
			shared = scope
		elif shared != scope:
			return ""
	return shared

## One effect line: what it does to which bucket. ADD reads as a flat amount, the
## two percentage ops as percentages, because that is how they are authored and
## how the rest of the game prints them.
##
## `with_scope` is false when the name above already carries it, so the scope is
## printed once per upgrade rather than once per line.
func _effect_text(effect: Dictionary, with_scope: bool) -> String:
	var mag: BigNumber = effect["mag"]
	var op := int(effect["op"])
	var value := ""
	match op:
		UpgradeEffectDef.Op.ADD:
			value = "+%s" % mag.to_display()
		UpgradeEffectDef.Op.MORE:
			value = "x%s" % mag.add(BigNumber.from_value(1.0)).to_display(2)
		_:
			value = "+%s%%" % mag.mul(BigNumber.from_value(100.0)).to_display()
	var scope := _scope_name(String(effect["key"])) if with_scope else ""
	var stat := String(effect["stat"]).capitalize()
	return "%s %s %s%s" % [value, StatResources.op_name(op), stat,
		"" if scope.is_empty() else " (%s)" % scope]

## The scope key as something readable, and "" for a global one - most effects
## are global and repeating "global" on every row is noise.
##
## A node key is turned back into the node's own name: "n:7" is the key the
## bucket is filed under, not something the player has ever seen.
func _scope_name(key: String) -> String:
	if key.begins_with("n:"):
		return _node_name(key.substr(2))
	if key.begins_with("t:"):
		return key.substr(2)
	return ""

func _track_name(track: String) -> String:
	match track:
		"prestige": return "Perks"
		"boosts": return "Crystal boosts"
		"projects": return "Well projects"
		"biome": return "Biome upgrades"
		_: return track.capitalize()
