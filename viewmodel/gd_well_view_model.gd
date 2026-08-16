class_name WellViewModel
extends ViewModel
## VIEWMODEL: the Well screen's own state - what the pump is doing and where the
## player left the list. Owns formatting and derived state.
## References the model, never a Node.
##
## The per-project cards bind their own VMs (App.project_vms); this one owns what
## is shared across the screen. The water balance is shown by the top bar, from
## the screen definition's currencies - this screen does not repeat it.

const PROP_PUMP_CHANGED := &"pump_changed"

# --- View state ---
## Where the player left this screen. Parked here because App owns ViewModels for
## the app's lifetime while the screen itself is freed on every nav switch. Same
## reasoning as CrystalCavesViewModel.scroll_offsets. Not saved: view state, not
## progress.
var scroll_offset := 0.0

# --- Read-only display properties bound by the View ---

## False after a sporation until the lake is bought back. The screen stays
## reachable either way (the tab is gated on ever-unlocked), so this is what tells
## the player why the water stopped.
var is_pumping: bool:
	get: return App.is_well_pumping()

var pump_text: String:
	get:
		if not is_pumping:
			return "The lake is sealed. Reopen Underground Lake to pump again."
		return "Pumps %s water every %d ticks - next in %d." % [
			App.water_pump_yield().to_display(), App.water_pump_interval(),
			App.ticks_until_water_pump()]

var project_vms_ordered: Array[ProjectViewModel]:
	get:
		var ordered: Array[ProjectViewModel] = []
		for def in App.projects.projects:
			ordered.append(App.project_vms[def.id])
		return ordered

# --- Lifecycle ---

func _init() -> void:
	# The countdown moves every tick, and the yield and interval move with any
	# track that touches the two water stats.
	App.player_data.tick_count_changed.connect(_on_pump_changed.unbind(1))
	App.biomes_data.biome_unlocked.connect(_on_pump_changed.unbind(1))
	App.upgrade_system.upgrades_changed.connect(_on_pump_changed)
	App.biome_upgrade_system.upgrades_changed.connect(_on_pump_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_pump_changed)
	App.boost_upgrade_system.upgrades_changed.connect(_on_pump_changed)
	App.project_upgrade_system.upgrades_changed.connect(_on_pump_changed)

func dispose() -> void:
	App.player_data.tick_count_changed.disconnect(_on_pump_changed.unbind(1))
	App.biomes_data.biome_unlocked.disconnect(_on_pump_changed.unbind(1))
	App.upgrade_system.upgrades_changed.disconnect(_on_pump_changed)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_pump_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_pump_changed)
	App.boost_upgrade_system.upgrades_changed.disconnect(_on_pump_changed)
	App.project_upgrade_system.upgrades_changed.disconnect(_on_pump_changed)

# --- Model -> notification plumbing ---

func _on_pump_changed() -> void:
	_notify(PROP_PUMP_CHANGED)
