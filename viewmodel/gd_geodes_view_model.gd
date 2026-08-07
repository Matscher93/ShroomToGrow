class_name GeodesViewModel
extends ViewModel
## VIEWMODEL: the Geodes tab's shared state - the exchange rate boosts are priced
## through, and what the crystal balance is currently worth in geodes.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## The per-boost cards bind their own VMs (App.geode_boost_vms); this one owns
## what is shared across the tab. The crystal balance itself is the Caves
## header's job, but crystals_changed still matters here: it moves the geode
## count this shows.

const PROP_GEODES_CHANGED := &"geodes_changed"

# --- Read-only display properties bound by the View ---

## Nothing is stored, so this is the crystal balance restated in geodes rather
## than a wallet of its own.
var available_text: String:
	get: return "%s geodes" % App.available_geodes().to_display()

var conversion_text: String:
	get: return "%s crystals each" % App.geode_conversion_rate().to_display()

func boost_vms_ordered() -> Array[GeodeBoostViewModel]:
	var ordered: Array[GeodeBoostViewModel] = []
	for def in App.geode_boosts.boosts:
		ordered.append(App.geode_boost_vms[def.id])
	return ordered

# --- Lifecycle ---

func _init() -> void:
	App.player_data.crystals_changed.connect(_on_crystals_changed)
	App.geode_upgrade_system.upgrades_changed.connect(_on_changed)

func dispose() -> void:
	App.player_data.crystals_changed.disconnect(_on_crystals_changed)
	App.geode_upgrade_system.upgrades_changed.disconnect(_on_changed)

# --- Model -> notification plumbing ---

func _on_crystals_changed(_value: BigNumber) -> void:
	_notify(PROP_GEODES_CHANGED)

## The conversion rate is a stat, so a bought upgrade can move it. Nothing does
## yet, but the display must not be the reason a later one looks broken.
func _on_changed() -> void:
	_notify(PROP_GEODES_CHANGED)
