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

# --- Biome sequence sections ---

## Sequence sections in biome order, unlocked ones only: a section for a biome
## the run hasn't reached would list upgrades the player can't see anywhere else.
func sequence_vms() -> Array[BiomeSequenceViewModel]:
	var sections: Array[BiomeSequenceViewModel] = []
	for def in App.biomes.biomes:
		if App.biomes_data.is_unlocked(def.key):
			sections.append(App.biome_sequence_vms[def.key])
	return sections

# --- Commands (called by the View on input) ---

func claim_all() -> BigNumber:
	return App.claim_all_achievements()

# --- Lifecycle ---

func _init() -> void:
	App.player_data.crystals_changed.connect(_on_crystals_changed)
	App.achievement_system.progress_changed.connect(_on_progress_changed)

func dispose() -> void:
	App.player_data.crystals_changed.disconnect(_on_crystals_changed)
	App.achievement_system.progress_changed.disconnect(_on_progress_changed)

# --- Model -> notification plumbing ---

func _on_crystals_changed(_value: BigNumber) -> void:
	_notify(PROP_CRYSTALS_TEXT)

func _on_progress_changed() -> void:
	_notify(PROP_TIERS_TEXT)
	_notify(PROP_CLAIM_ALL)
