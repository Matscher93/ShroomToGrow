class_name CrystalCavesViewModel
extends ViewModel
## VIEWMODEL: the Crystal Caves screen's own state - the crystal balance and the
## point plan the SPEND_BIOME_POINTS automation follows. Owns formatting and
## derived state.
## References the model, never a Node.
##
## The per-automation cards bind their own VMs (App.automation_vms); this one
## owns what is shared across the screen. The achievement archive the crystals
## come from lives in the top-bar overlay (App.achievements_vm), not here.

const PROP_CRYSTALS_TEXT := &"crystals_text"

# --- Read-only display properties bound by the View ---
var crystals_text: String:
	get: return App.player_data.crystals.to_display()

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

# --- Biome auto-unlock rows ---

## The auto-unlock rows on the Automations tab, in biome order. Gated on
## ever_unlocked rather than on the run's own unlocked set, unlike the sequence
## sections above: buying this row's automation is exactly what a player does for
## a biome that is currently shut, and the filter that hides the sections would
## hide the row on every run before the biome is bought back.
##
## Starter biomes are still left out - a row that can only ever say "never
## relocks" is a line of noise between the ones with a switch.
func auto_unlock_vms() -> Array[BiomeSequenceViewModel]:
	var rows: Array[BiomeSequenceViewModel] = []
	for def in App.biomes.biomes:
		if not App.biomes_data.is_ever_unlocked(def.key):
			continue
		var vm: BiomeSequenceViewModel = App.biome_sequence_vms[def.key]
		if vm.offers_auto_unlock:
			rows.append(vm)
	return rows

# --- Lifecycle ---

func _init() -> void:
	App.player_data.crystals_changed.connect(_on_crystals_changed)

func dispose() -> void:
	App.player_data.crystals_changed.disconnect(_on_crystals_changed)

# --- Model -> notification plumbing ---

func _on_crystals_changed(_value: BigNumber) -> void:
	_notify(PROP_CRYSTALS_TEXT)
