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

## Bonus-tab fold state, keyed by resource name and by "resource/track". Absent
## means the default in both cases - see is_resource_open()/is_track_open().
var _open_resources: Dictionary = {}
var _closed_tracks: Dictionary = {}

# --- Read-only display properties bound by the View ---

## {key, label, value} rows. The lifetime totals sit alongside the peaks: "most
## held" and "earned in total" answer different questions and a player reading a
## records tab wants both.
##
## `key` says what the row is about, not what it says - the view maps it to an
## icon, and the run rows below use the same key space so one table covers both
## tabs. It is deliberately not the label: a renamed label must not silently
## change which icon a row draws.
var records_rows: Array[Dictionary]:
	get:
		var stats := App.stats_data
		var player := App.player_data
		var rows: Array[Dictionary] = []
		rows.append({"key": &"first_played", "label": "Playing since",
			"value": TimeFormat.stamp(stats.first_played_at)})
		rows.append({"key": &"current_run", "label": "Current run",
			"value": _current_run_duration()})
		for pair: Array in _PEAK_LABELS:
			rows.append({"key": pair[0], "label": pair[1],
				"value": stats.peak(pair[0]).to_display()})
		for pair: Array in _COUNT_LABELS:
			rows.append({"key": pair[0], "label": pair[1],
				"value": "%d" % stats.count(pair[0])})
		rows.append({"key": &"lifetime_nutrients", "label": "Lifetime nutrients",
			"value": player.lifetime_nutrients.to_display()})
		rows.append({"key": &"lifetime_crystals", "label": "Lifetime crystals",
			"value": player.lifetime_crystals.to_display()})
		rows.append({"key": &"lifetime_ticks", "label": "Lifetime ticks",
			"value": "%d" % player.lifetime_ticks})
		rows.append({"key": &"lifetime_manual_nodes", "label": "Nodes bought, ever",
			"value": "%d" % player.lifetime_manual_nodes})
		rows.append({"key": &"lifetime_biome_size", "label": "Biome size bought, ever",
			"value": "%d" % player.lifetime_biome_size})
		rows.append({"key": &"events_resolved", "label": "Events resolved",
			"value": "%d" % player.events_resolved})
		rows.append({"key": &"prestige_count", "label": "Sporations",
			"value": "%d" % player.prestige_count})
		return rows

## {kind, key, title, detail, when} rows, newest first - a timeline is read from
## the end a player was last at.
##
## `kind` and `key` are passed through raw so the view can draw the milestone's
## own icon: a biome one has an authored shader on its BiomeDef, which is a
## static registry field and stays a view-side lookup rather than something a
## ViewModel hands out.
var milestone_rows: Array[Dictionary]:
	get:
		var rows: Array[Dictionary] = []
		var milestones: Array = App.stats_data.milestones
		for i in range(milestones.size() - 1, -1, -1):
			var row: Dictionary = milestones[i]
			var titled := _milestone_title(row)
			rows.append({
				"kind": String(row.get("kind", "")),
				"key": String(row.get("key", "")),
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

# --- Bonus-tab fold state ---
#
# Not notified: the view toggles and rebuilds itself through its own PressGuard,
# and a _notify() here would only ask it to do the same rebuild a second time.
#
# Kept across refresh_bonuses() and across the overlay being closed, which is why
# it lives on this App-owned ViewModel rather than on the panel the PopupLayer
# frees. Keyed by name, so an entry left behind by a renamed track is inert.

## Which resource cards the player has opened. A resource starts closed: the tab
## is otherwise every levelled upgrade in all eight tracks at once, which is what
## made it unreadable.
func is_resource_open(resource: String) -> bool:
	return _open_resources.get(resource, false)

func toggle_resource(resource: String) -> void:
	_open_resources[resource] = not is_resource_open(resource)

## Which track groups inside an opened resource the player has closed. A track
## starts open: opening the resource above it is the request to see what is in
## it, so folding those too would take two presses to see anything.
func is_track_open(resource: String, track: String) -> bool:
	return not _closed_tracks.get(_track_path(resource, track), false)

func toggle_track(resource: String, track: String) -> void:
	var path := _track_path(resource, track)
	_closed_tracks[path] = is_track_open(resource, track)

func _track_path(resource: String, track: String) -> String:
	return "%s/%s" % [resource, track]

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
			{"key": &"current_run", "label": "Played", "value": _current_run_duration()},
			{"key": &"tick_count", "label": "Ticks", "value": "%d" % player.tick_count},
			{"key": &"nutrients", "label": "Nutrients", "value": player.nutrients.to_display()},
			{"key": &"water", "label": "Water", "value": player.water.to_display()},
			{"key": &"biomass", "label": "Biomass so far",
				"value": App.prestige_system.preview_biomass_gain().to_display()},
			{"key": &"crystals", "label": "Crystals", "value": player.crystals.to_display()},
			{"key": &"relics", "label": "Relics", "value": player.relics.to_display()},
			{"key": &"ichor", "label": "Ichor", "value": player.ichor.to_display()},
			{"key": &"glyphs", "label": "Glyphs", "value": player.glyphs.to_display()},
			{"key": &"production", "label": "Production/tick",
				"value": App.total_production().to_display()},
			{"key": &"manual_nodes", "label": "Nodes",
				"value": "%d" % App.stats_data.count(&"manual_nodes")},
			{"key": &"perk_levels", "label": "Perk levels",
				"value": "%d" % App.prestige_upgrade_system.total_levels()},
			{"key": &"symbiosis_levels", "label": "Symbiosis levels",
				"value": "%d" % App.upgrade_system.total_levels()},
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
			{"key": &"current_run", "label": "Played", "value": played},
			{"key": &"tick_count", "label": "Ticks", "value": "%d" % int(record.get("ticks", 0))},
			{"key": &"nutrients", "label": "Nutrients",
				"value": _saved_number(record, "nutrients")},
			{"key": &"water", "label": "Water", "value": _saved_number(record, "water")},
			{"key": &"biomass", "label": "Biomass gained",
				"value": _saved_number(record, "biomass_gained")},
			{"key": &"crystals", "label": "Crystals",
				"value": _saved_number(record, "crystals")},
			{"key": &"relics", "label": "Relics", "value": _saved_number(record, "relics")},
			{"key": &"ichor", "label": "Ichor", "value": _saved_number(record, "ichor")},
			{"key": &"glyphs", "label": "Glyphs", "value": _saved_number(record, "glyphs")},
			{"key": &"production", "label": "Production/tick",
				"value": _saved_number(record, "peak_production")},
			{"key": &"manual_nodes", "label": "Nodes",
				"value": "%d" % int(record.get("manual_nodes", 0))},
			{"key": &"perk_levels", "label": "Perk levels",
				"value": "%d" % int(record.get("perk_levels", 0))},
			{"key": &"symbiosis_levels", "label": "Symbiosis levels",
				"value": "%d" % int(record.get("symbiosis_levels", 0))},
			{"key": &"deepest_biome", "label": "Deepest biome",
				"value": deepest if not deepest.is_empty() else "-",
				"biome": _biome_key(deepest)},
		],
	}

## A number a finished run wrote, or "-" where that run never wrote one.
##
## The two are not the same and the difference is visible: runs recorded before
## the currency balances were kept have no key at all, and printing those as 0
## would claim a player ended that run with nothing rather than that nobody was
## counting. A run that genuinely held none still stores a zero and prints it.
func _saved_number(record: Dictionary, key: String) -> String:
	if not record.has(key):
		return "-"
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
			return ["Grew %s" % ScopeLabel.node_name(key), _node_detail(key, run)]
		StatsSystem.MILESTONE_PRESTIGE:
			return ["Sporated (run %s)" % key, "Traded the run in for biomass"]
		_:
			return [key, ""]

func _biome_name(key: String) -> String:
	for def in App.biomes.biomes:
		if String(def.key) == key:
			return def.display_name
	return key

## The biome key behind a name a finished run recorded, or "" when nothing
## matches. The view turns it into that biome's own colour.
##
## Matched on the display name because that is what StatsSystem._deepest_biome()
## writes into the record - a key was never stored. So a biome renamed after a
## run ended loses its tint on that row and keeps the name it was reached under,
## which is the honest pair: the record says where the player got to at the time.
func _biome_key(display_name: String) -> String:
	if display_name.is_empty():
		return ""
	for def in App.biomes.biomes:
		if def.display_name == display_name:
			return String(def.key)
	return ""

## Which tier of node this was, said the way the node panel already says it.
##
## node_id *is* the tier, and MyceliumNodeViewModel._unit_text() prints it as
## "LV%d" - except for node 0, the Mycelium, which it leaves bare because there
## is no level 0 to speak of. The timeline follows both halves of that: a
## milestone reading "LV0 node" would name a tier the rest of the game does not.
func _node_detail(node_id: String, run: int) -> String:
	var level := int(node_id)
	if level <= 0:
		return "First grown during run %d" % [run + 1]
	return "LV%d node - first grown during run %d" % [level, run + 1]

## The model's groups with every number turned into the string a row prints.
## Formatting lives here rather than in BonusBreakdown so the model stays
## comparable and the view stays free of BigNumber.
func _build_bonus_groups() -> Array:
	var out: Array = []
	for group: Dictionary in BonusBreakdown.build(App.production_system):
		# [multiplier, row] pairs, so the tracks can be ranked by a number the
		# rows themselves only carry as text. Dropped again below - a sort key is
		# not something the view has any use for.
		var ranked: Array = []
		for source: Dictionary in group["sources"]:
			var upgrades: Array = []
			var track_effects: Array = []
			for upgrade: Dictionary in source["upgrades"]:
				var scope := ScopeLabel.of_keys(upgrade["effects"])
				track_effects.append_array(upgrade["effects"] as Array)
				var display_name := String(upgrade["name"])
				if display_name.is_empty():
					display_name = String(upgrade["id"])
				if not scope.is_empty():
					display_name = "%s - %s" % [display_name, scope]
				upgrades.append({
					# The level is what an upgrade *cost*, the multiplier is what
					# it *does*, and only one of those fits in the value column.
					# The level rides along in the name so the pair stays legible
					# on one line rather than dropping out of the tab.
					"name": "%s - Lv %d" % [display_name, int(upgrade["level"])],
					"multiplier": _multiplier_text(upgrade["effects"]),
				})
			ranked.append([_sort_weight(track_effects), {
				"track": _track_name(source["track"]),
				"multiplier": _multiplier_text(track_effects),
				"upgrades": upgrades,
			}])
		# Heaviest track first, which is not the order BonusBreakdown hands them
		# over in: that one is the stacking order, the order the game applies the
		# tracks in. Stacking order explains the header number, and it is the
		# right default for a model that does not know it is being looked at. A
		# reader opening a resource is asking what is doing the most work.
		ranked.sort_custom(func(a: Array, b: Array) -> bool:
			return (a[0] as BigNumber).gt(b[0] as BigNumber))
		var sources: Array = []
		for pair: Array in ranked:
			sources.append(pair[1])
		out.append({
			"resource": String(group["resource"]).capitalize(),
			"total": _total_text(group),
			"count": "%d upgrade%s" % [group["upgrade_count"],
				"" if group["upgrade_count"] == 1 else "s"],
			"sources": sources,
		})
	return out

## What a set of effects multiplies its buckets by, as the row prints it.
##
## MORE and INCREASED both read as x(1+mag): exact for a MORE, and for an
## INCREASED it is what that upgrade alone is worth rather than its share of a
## bucket it adds into alongside others. Same honesty BonusBreakdown documents -
## exact rather than comparable. Multiplying the two together is the same
## overstatement in the other direction and is what the header's own total is
## there to correct: the number in the card's title is resolved by the game,
## these are the parts.
##
## Effects that only ADD have no multiplier to show at all - a flat +6 nutrients
## is not an x7 of anything - so those print their total instead.
func _resolve(effects: Array) -> Dictionary:
	var multiplier := BigNumber.from_value(1.0)
	var flat := BigNumber.new(0.0, 0)
	var has_multiplier := false
	for effect: Dictionary in effects:
		var mag: BigNumber = effect["mag"]
		if int(effect["op"]) == UpgradeEffectDef.Op.ADD:
			flat = flat.add(mag)
			continue
		multiplier = multiplier.mul(mag.add(BigNumber.from_value(1.0)))
		has_multiplier = true
	return {"multiplier": multiplier, "flat": flat, "has_multiplier": has_multiplier}

## The above as the row prints it. An x1 from a set of pure ADDs and an x1 from a
## levelled multiplier are the same number and very different rows, so a set that
## never multiplied prints its amount instead.
func _multiplier_text(effects: Array) -> String:
	var resolved := _resolve(effects)
	if resolved["has_multiplier"]:
		return "x%s" % (resolved["multiplier"] as BigNumber).to_display(2)
	return _amount_text(resolved["flat"])

## What the track sort ranks on: the multiplier where there is one, the size of
## the flat total where there is not.
##
## Without the second half tick speed sorts arbitrarily. Every one of its tracks
## is pure ADD, so every multiplier comes out at exactly 1.0 and the comparison
## has nothing to separate them by - the order it happened to land in was luck.
## Unsigned, because those amounts are seconds off an interval: -9.0 is the
## bigger contribution, not the smaller.
func _sort_weight(effects: Array) -> BigNumber:
	var resolved := _resolve(effects)
	if resolved["has_multiplier"]:
		return resolved["multiplier"]
	var flat: BigNumber = resolved["flat"]
	return BigNumber.new(absf(flat.mantissa), flat.exponent)

## A flat amount with its sign, and no "x" anywhere near it.
##
## to_display() already writes the minus, so only a positive needs a sign added -
## "+%s" over a negative is what printed the tick-speed rows as "+-11.7". Every
## tick_rate and water_rate effect is authored as seconds *off* an interval, so
## that whole resource is negative and none of it is a multiplier.
func _amount_text(amount: BigNumber) -> String:
	if amount.mantissa > 0.0:
		return "+%s" % amount.to_display()
	return amount.to_display()

## The number in a resource card's header.
##
## An additive resource has no multiplier to print: tick speed resolves to the
## seconds its upgrades take off the interval, so it prints as the amount it is.
## Where the total had to be resolved against one node to include that node's
## own effects, the header says which - it is that node's number, not everyone's.
func _total_text(group: Dictionary) -> String:
	var total: BigNumber = group["total"]
	var text := _amount_text(total) if group["additive"] else "x%s" % total.to_display(2)
	var scope := ScopeLabel.of_key(String(group["total_scope"]))
	return text if scope.is_empty() else "%s (%s)" % [text, scope]

func _track_name(track: String) -> String:
	match track:
		"prestige": return "Perks"
		"boosts": return "Crystal boosts"
		"projects": return "Well projects"
		"biome": return "Biome upgrades"
		_: return track.capitalize()
