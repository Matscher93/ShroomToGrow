class_name AchievementsViewModel
extends ViewModel
## VIEWMODEL: the achievement overlay as a whole - the lifetime tier count, the
## claim-all button, and whether anything is waiting to be collected. Owns
## formatting and derived state.
## References the model, never a Node.
##
## The per-achievement rows bind their own VMs (App.achievement_vms); this one
## owns what is shared across the overlay, plus the has_claims flag the top-bar
## button's notification dot reads.
##
## Built once in App._ready() and owned for the app's lifetime, mirroring
## App.achievement_vms: the top-bar button is on screen whether the overlay is
## open or not, so a per-open VM would still have to exist while it is closed.

const PROP_TIERS_TEXT := &"tiers_text"
const PROP_CLAIM_ALL := &"claim_all_text"
const PROP_HAS_CLAIMS := &"has_claims"
const PROP_VISIBLE := &"visible"

# --- Read-only display properties bound by the View ---
var tiers_text: String:
	get:
		var total := App.achievement_system.total_tiers()
		return "%d achievement%s claimed" % [total, "" if total == 1 else "s"]

## Drives both the claim-all button's enabled state and the top-bar dot.
var has_claims: bool:
	get: return App.has_achievement_claims()

## Whether the top-bar button that opens this overlay belongs on screen at all.
## Tiers pay crystals and nothing else, and crystals have nowhere to be spent or
## even shown until the Crystal Caves screen exists - so before that the archive
## is an entry point to a currency the player cannot use. Read off the permanent
## record rather than the run's own set: the caves stay claimed across a prestige
## reset, and so does the button.
var is_visible: bool:
	get: return App.is_screen_unlocked(ScreenTypes.Types.CRYSTAL_CAVES)

var claim_all_text: String:
	get:
		var waiting := App.achievement_system.total_unclaimed()
		if waiting <= 0:
			return "Nothing to claim"
		return "Claim all (%d)" % [waiting]

## Achievement rows in authored order, so the archive reads the same every time.
var achievement_vms_ordered: Array[AchievementViewModel]:
	get:
		var ordered: Array[AchievementViewModel] = []
		for def in App.achievements.achievements:
			ordered.append(App.achievement_vms[def.id])
		return ordered

# --- Commands (called by the View on input) ---

func claim_all() -> BigNumber:
	return App.claim_all_achievements()

# --- Lifecycle ---

func _init() -> void:
	App.achievement_system.progress_changed.connect(_on_progress_changed)
	# Reaching the Crystal Caves is what reveals the button, and it is bought from
	# a biome card rather than from anywhere this overlay can see.
	App.biomes_data.biome_unlocked.connect(_on_biome_unlocked.unbind(1))

func dispose() -> void:
	App.achievement_system.progress_changed.disconnect(_on_progress_changed)
	App.biomes_data.biome_unlocked.disconnect(_on_biome_unlocked.unbind(1))

# --- Model -> notification plumbing ---

func _on_progress_changed() -> void:
	_notify(PROP_TIERS_TEXT)
	_notify(PROP_CLAIM_ALL)
	_notify(PROP_HAS_CLAIMS)

func _on_biome_unlocked() -> void:
	_notify(PROP_VISIBLE)
