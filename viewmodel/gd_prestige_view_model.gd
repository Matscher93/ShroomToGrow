class_name PrestigeViewModel
extends ViewModel
## VIEWMODEL: the prestige/sporate action. Pending biomass gain preview and
## whether prestiging is allowed. Per-perk detail lives in PerkViewModel
## (App.perk_vms). References the model, never a Node.

const PROP_PENDING_CHANGED := &"pending_changed"
## Something a perk node's look depends on moved - a purchase, or the biomass
## that decides which of them are affordable. Separate from
## PROP_PENDING_CHANGED so the sporate button and the web can each refresh only
## what they own, even though the same sources feed both.
const PROP_PERKS_CHANGED := &"perks_changed"

# --- Read-only display properties bound by the View ---
var sporate_text: String:
	get:
		var pending := App.preview_biomass_gain()
		return "Sporate (+%s biomass · resets colony, keeps perks)" % pending.to_display()

var sporate_enabled: bool:
	get: return App.can_prestige()

## Short form for the resource bar's biomass chip, where the full sporate
## sentence does not fit.
var pending_biomass_text: String:
	get:
		return "+%s on sporate" % App.preview_biomass_gain().to_display()

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
	_notify(PROP_PERKS_CHANGED)
