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

# --- Read-only display properties bound by the View ---
var tiers_text: String:
	get:
		var total := App.achievement_system.total_tiers()
		return "%d achievement%s claimed" % [total, "" if total == 1 else "s"]

## Drives both the claim-all button's enabled state and the top-bar dot.
var has_claims: bool:
	get: return App.has_achievement_claims()

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

func dispose() -> void:
	App.achievement_system.progress_changed.disconnect(_on_progress_changed)

# --- Model -> notification plumbing ---

func _on_progress_changed() -> void:
	_notify(PROP_TIERS_TEXT)
	_notify(PROP_CLAIM_ALL)
	_notify(PROP_HAS_CLAIMS)
