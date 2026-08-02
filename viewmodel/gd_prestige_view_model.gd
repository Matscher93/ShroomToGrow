class_name PrestigeViewModel
extends ViewModel
## VIEWMODEL: the prestige/sporate action. Pending biomass gain preview and
## whether prestiging is allowed. Per-perk detail lives in PerkViewModel
## (App.perk_vms). References the model, never a Node.

const PROP_PENDING_CHANGED := &"pending_changed"

# --- Read-only display properties bound by the View ---
var sporate_text: String:
	get:
		var pending := App.preview_biomass_gain()
		return "Sporate (+%s biomass · resets colony, keeps perks)" % pending.to_display()

var sporate_enabled: bool:
	get: return App.can_prestige()

# --- Lifecycle ---

func _init() -> void:
	# unbind(1) drops the BigNumber the currency signals carry, so the handler
	# stays parameterless.
	App.player_data.biomass_changed.connect(_on_changed.unbind(1))
	App.player_data.nutrients_changed.connect(_on_changed.unbind(1))
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	# Biome upgrades feed &"biomass_gain" too (PermafrostUpgrade2/10), and their
	# Biome Size dependency re-emits this on invalidate().
	App.biome_upgrade_system.upgrades_changed.connect(_on_changed)

func dispose() -> void:
	App.player_data.biomass_changed.disconnect(_on_changed.unbind(1))
	App.player_data.nutrients_changed.disconnect(_on_changed.unbind(1))
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_changed)

# --- Commands (called by the View on input) ---

func sporate() -> void:
	App.prestige()

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_PENDING_CHANGED)
