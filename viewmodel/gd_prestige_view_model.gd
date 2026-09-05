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

## The two storage bars. Read once per refresh through the model's own report, so
## the View never re-derives a ladder - see PrestigeSystem.storage_report().
var nutrient_storage_text: String:
	get:
		var report := App.prestige_system.storage_report()
		return _storage_text("Nutrient storage", report["nutrient_areas"],
			report["nutrient_amount"], report["nutrient_next"])

var nutrient_storage_fill: float:
	get: return App.prestige_system.storage_report()["nutrient_fill"]

var tick_storage_text: String:
	get:
		var report := App.prestige_system.storage_report()
		return _storage_text("Time storage", report["tick_areas"],
			report["tick_amount"], report["tick_next"])

var tick_storage_fill: float:
	get: return App.prestige_system.storage_report()["tick_fill"]

## Why the button is off, when it is off. Empty while a sporate is available, so
## the View can hide the line rather than show an inert sentence.
var gate_text: String:
	get:
		if sporate_enabled:
			return ""
		if not App.biomes_data.is_unlocked(PrestigeSystem.GATE_BIOME):
			return "Reach permafrost to sporate."
		var report := App.prestige_system.storage_report()
		var best: BigNumber = report["best"]
		return "Fill more storage: this run pays %s, your best was %s." % [
			(report["gain"] as BigNumber).to_display(), best.to_display()]

## "Nutrient storage · 4 filled · 12.3K / 100.0K": what the ladder has finished,
## then how far into the one being filled - as the two amounts rather than as a
## percentage, which said nothing about how much further it is. The pair is not
## labelled as the next area's price: it sits above that area's own bar.
func _storage_text(label: String, areas: int, amount: BigNumber, needed: BigNumber) -> String:
	return "%s · %d filled · %s / %s" % [
		label, areas, amount.to_display(), needed.to_display()]

## Short form for the resource bar's biomass chip, where the full sporate
## sentence does not fit.
var pending_biomass_text: String:
	get:
		return "+%s on sporate" % App.preview_biomass_gain().to_display()

# --- Lifecycle ---

## Every upgrade track ProductionSystem.stack_external() runs a stat through -
## which is exactly what decides the numbers on this screen: &"biomass_gain" on
## the payout, and &"tick_area_cost"/&"nutrient_area_growth" on the two storage
## ladders that feed it. A level bought in any of them moves the pending gain, so
## a track missing from here left the preview reading a purchase behind until the
## next tick happened to refresh it - which is how a Level Point spent on the
## biomass producer (&"biomass_gain", global, through the growth track) showed up
## a tick late.
##
## Listed once so the connect and the disconnect cannot drift, and so a tenth
## track added to stack_external is added here rather than silently going
## unwatched. Symbiosis is deliberately absent, for the reason stack_external
## skips it: the sporation is about to wipe those levels, so they must not price
## the trade.
func _gain_tracks() -> Array[UpgradeSystem]:
	return [
		# Biome upgrades feed &"biomass_gain" (PermafrostUpgrade2/10), and their
		# Biome Size dependency re-emits this on invalidate().
		App.biome_upgrade_system,
		App.prestige_upgrade_system,
		App.boost_upgrade_system,
		App.project_upgrade_system,
		App.growth_upgrade_system,
		App.fertilizer_upgrade_system,
		App.mission_upgrade_system,
		App.expedition_upgrade_system,
	]

func _init() -> void:
	# unbind(1) drops the BigNumber the currency signals carry, so the handler
	# stays parameterless.
	App.player_data.biomass_changed.connect(_on_changed.unbind(1))
	App.player_data.nutrients_changed.connect(_on_changed.unbind(1))
	# Ticks fill the time storage on their own, so the bars and the payout move
	# on a tick that produced nothing.
	App.player_data.tick_count_changed.connect(_on_changed.unbind(1))
	for track in _gain_tracks():
		track.upgrades_changed.connect(_on_changed)

func dispose() -> void:
	App.player_data.biomass_changed.disconnect(_on_changed.unbind(1))
	App.player_data.nutrients_changed.disconnect(_on_changed.unbind(1))
	App.player_data.tick_count_changed.disconnect(_on_changed.unbind(1))
	for track in _gain_tracks():
		track.upgrades_changed.disconnect(_on_changed)

# --- Commands (called by the View on input) ---

func sporate() -> void:
	App.prestige()

# --- Model -> notification plumbing ---

func _on_changed() -> void:
	_notify(PROP_PENDING_CHANGED)
	_notify(PROP_PERKS_CHANGED)
