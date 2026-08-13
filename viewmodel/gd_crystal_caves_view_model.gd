class_name CrystalCavesViewModel
extends ViewModel
## VIEWMODEL: the Crystal Caves screen's own state - which tabs are up, where the
## player left them, and the point plan the SPEND_BIOME_POINTS automation
## follows. Owns formatting and derived state.
## References the model, never a Node.
##
## The per-automation cards bind their own VMs (App.automation_vms); this one
## owns what is shared across the screen. The achievement archive the crystals
## come from lives in the top-bar overlay (App.achievements_vm), not here. The
## crystal balance is shown by the top bar, from the screen definition's
## currencies - this screen does not repeat it.

const PROP_GEODES_VISIBLE := &"geodes_visible"
const PROP_SECTIONS_CHANGED := &"sections_changed"

# --- View state ---
## Where the player left this screen. Parked here because App owns ViewModels for
## the app's lifetime while the screen itself is freed on every nav switch, and
## re-finding a tab and a scroll position on every visit is the single most
## expensive thing this screen asks of the player. Same reasoning as
## BiomeSequenceViewModel._page. Not saved: view state, not progress.
var current_tab := 0
## Scroll offset per scrolling tab, keyed by tab index.
var scroll_offsets: Dictionary = {}

# --- Read-only display properties bound by the View ---
## Whether the Geodes tab belongs on screen at all. Every boost is behind its own
## prestige perk, so before the first of them the tab is a page of locked cards
## explaining a currency the player has no way to spend - one tab too many on a
## screen reached from a phone's thumb.
var geodes_visible: bool:
	get:
		for def in App.geode_boosts.boosts:
			if App.is_geode_boost_unlocked(def.id):
				return true
		return false

var automation_vms_ordered: Array[AutomationViewModel]:
	get:
		var ordered: Array[AutomationViewModel] = []
		for def in App.automations.automations:
			ordered.append(App.automation_vms[def.id])
		return ordered

# --- Biome sequence sections ---

## Sequence sections in biome order, for every biome the save has ever reached.
##
## Gated on ever_unlocked rather than on the run's own unlocked set, because each
## section also carries that biome's auto-buy-after-sporation purchase, and
## buying it is exactly what a player does for a biome that is currently shut.
## The run's own set would hide the section on every run before the biome is
## bought back - which is every run where the purchase is worth making.
##
## A section for a biome shut this run shows its auto-buy with the slot grid
## dead: there is nothing to plan against until the biome is open again.
func sequence_vms() -> Array[BiomeSequenceViewModel]:
	var sections: Array[BiomeSequenceViewModel] = []
	for def in App.biomes.biomes:
		if App.biomes_data.is_ever_unlocked(def.key):
			sections.append(App.biome_sequence_vms[def.key])
	return sections

# --- Lifecycle ---

func _init() -> void:
	# Buying the first geode unlock perk is what brings the tab in, and that can
	# happen while this screen is open - the perk web is a screen away.
	App.prestige_upgrade_system.upgrades_changed.connect(_on_perks_changed)
	# Reaching a biome adds its section. The screen used to be rebuilt on every
	# nav switch, which hid the need for this; now that it keeps its state, a
	# biome unlocked while the screen is up has to bring its own section in.
	App.biomes_data.biome_unlocked.connect(_on_sections_changed.unbind(1))

func dispose() -> void:
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_perks_changed)
	App.biomes_data.biome_unlocked.disconnect(_on_sections_changed.unbind(1))

# --- Model -> notification plumbing ---

func _on_perks_changed() -> void:
	_notify(PROP_GEODES_VISIBLE)

func _on_sections_changed() -> void:
	_notify(PROP_SECTIONS_CHANGED)
