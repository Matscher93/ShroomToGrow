class_name CrystalCavesViewModel
extends ViewModel
## VIEWMODEL: the Crystal Caves screen's own state - the crystal balance, the
## lifetime achievement count, and the point plan the SPEND_BIOME_POINTS
## automation follows. Owns formatting and derived state.
## References the model, never a Node.
##
## The per-achievement and per-automation rows bind their own VMs
## (App.achievement_vms / App.automation_vms); this one owns what is shared
## across the screen.

const PROP_CRYSTALS_TEXT := &"crystals_text"
const PROP_TIERS_TEXT := &"tiers_text"
const PROP_CLAIM_ALL := &"claim_all_text"
const PROP_PLAN_CHANGED := &"plan_changed"

# --- Read-only display properties bound by the View ---
var crystals_text: String:
	get: return App.player_data.crystals.to_display()

var tiers_text: String:
	get:
		var total := App.achievement_system.total_tiers()
		return "%d achievement%s claimed" % [total, "" if total == 1 else "s"]

var has_claims: bool:
	get: return App.has_achievement_claims()

var claim_all_text: String:
	get:
		var waiting := App.achievement_system.total_unclaimed()
		if waiting <= 0:
			return "Nothing to claim"
		return "Claim all (%d)" % [waiting]

## Carries the pending-claim count onto the tab itself, so a player sitting on
## the upgrades tab can still see that something is waiting next door.
var achievements_tab_text: String:
	get:
		var waiting := App.achievement_system.total_unclaimed()
		if waiting <= 0:
			return "Achievements"
		return "Achievements (%d)" % [waiting]

## Achievement rows in authored order, so the archive reads the same every time.
var achievement_vms_ordered: Array[AchievementViewModel]:
	get:
		var ordered: Array[AchievementViewModel] = []
		for def in App.achievements.achievements:
			ordered.append(App.achievement_vms[def.id])
		return ordered

var automation_vms_ordered: Array[AutomationViewModel]:
	get:
		var ordered: Array[AutomationViewModel] = []
		for def in App.automations.automations:
			ordered.append(App.automation_vms[def.id])
		return ordered

# --- Point plan ---

## Only unlocked biomes: a plan for a biome the run hasn't reached yet would list
## upgrades the player can't see anywhere else.
func planned_biomes() -> Array[BiomeDef]:
	var planned: Array[BiomeDef] = []
	for def in App.biomes.biomes:
		if App.biomes_data.is_unlocked(def.key):
			planned.append(def)
	return planned

## One row per entry in the biome's plan, in the order the automation buys them.
## Each row is {id, name, target, target_text, level_text}.
func plan_rows(biome_key: StringName) -> Array[Dictionary]:
	var def := App.biome_def(biome_key)
	if def == null:
		return []
	var rows: Array[Dictionary] = []
	for entry: Dictionary in App.automation_data.plan_for(biome_key, def.upgrade_ids):
		var id := StringName(entry.get("id", &""))
		var target := int(entry.get("target", 0))
		var upgrade_def := App.biome_upgrade_system.def(id)
		rows.append({
			"id": id,
			"name": upgrade_def.display_name if upgrade_def != null else String(id),
			"target": target,
			"target_text": "any" if target <= 0 else "to %d" % [target],
			"level_text": "Lv %d" % [App.biome_upgrade_system.level(id)],
		})
	return rows

# --- Commands (called by the View on input) ---

func claim_all() -> BigNumber:
	return App.claim_all_achievements()

func move_plan_entry_up(biome_key: StringName, index: int) -> bool:
	return App.automation_data.move_entry(biome_key, index, index - 1)

func move_plan_entry_down(biome_key: StringName, index: int) -> bool:
	return App.automation_data.move_entry(biome_key, index, index + 1)

## Cycles the target through 0 (buy until maxed) and 1..max_level, so one tap per
## row is enough on touch, with no spinner to hit.
func cycle_plan_target(biome_key: StringName, index: int) -> void:
	var rows := plan_rows(biome_key)
	if index < 0 or index >= rows.size():
		return
	var upgrade_def := App.biome_upgrade_system.def(rows[index]["id"])
	var cap: int = upgrade_def.max_level if upgrade_def != null and upgrade_def.max_level > 0 else 10
	var next: int = int(rows[index]["target"]) + 1
	if next > cap:
		next = 0
	App.automation_data.set_target_level(biome_key, index, next)

# --- Lifecycle ---

func _init() -> void:
	App.player_data.crystals_changed.connect(_on_crystals_changed)
	App.achievement_system.progress_changed.connect(_on_progress_changed)
	App.automation_data.point_plan_changed.connect(_on_plan_changed.unbind(1))
	# A purchase moves the Lv text on every plan row.
	App.biome_upgrade_system.upgrades_changed.connect(_on_plan_changed)

func dispose() -> void:
	App.player_data.crystals_changed.disconnect(_on_crystals_changed)
	App.achievement_system.progress_changed.disconnect(_on_progress_changed)
	App.automation_data.point_plan_changed.disconnect(_on_plan_changed.unbind(1))
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_plan_changed)

# --- Model -> notification plumbing ---

func _on_crystals_changed(_value: BigNumber) -> void:
	_notify(PROP_CRYSTALS_TEXT)

func _on_progress_changed() -> void:
	_notify(PROP_TIERS_TEXT)
	_notify(PROP_CLAIM_ALL)

func _on_plan_changed() -> void:
	_notify(PROP_PLAN_CHANGED)
