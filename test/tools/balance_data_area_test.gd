extends GdUnitTestSuite
## BalanceData.area_of() and identity_of() (tools/gd_balance_data.gd).
##
## Every priced def has to land in a lane and name a currency, because the spread
## view lanes the whole game off these two and a def that resolves to neither is
## a price nobody can see. Nothing else checks that: AREAS is a prefix table, so
## a new folder under data/ - or a folder renamed - simply stops matching and the
## defs inside it go quiet rather than failing.
##
## identity_of() is the other half. It is the only join between a cost curve and
## what the simulator recorded buying, and a PerkDef is built at runtime by
## PerkTree with no resource_path to be joined by instead.

const DATA := preload("res://tools/gd_balance_data.gd")
const DATA_DIR := "res://data"

## The PlayerData fields UpgradeSystem.buy() can actually spend, plus the two
## labels for things that are bought with something that is not a currency:
## biome points, which BiomeSystem holds, and nothing at all.
const SPENDABLE := ["nutrients", "water", "biomass", "crystals", "relics", "ichor",
	"glyphs", "fertilizer", "biome_points", ""]

var _report: Dictionary

func before() -> void:
	_report = DATA.curves(DATA_DIR)

# ─── Every priced def is placed ──────────────────────────────────────────────

func test_every_priced_def_lands_in_an_area() -> void:
	var homeless: Array[String] = []
	for bucket: String in _priced_buckets():
		for path: String in _report[bucket]:
			if String(_report[bucket][path].get("area", "")).is_empty():
				homeless.append(path)
	assert_array(homeless).override_failure_message(
		"These priced defs match no prefix in BalanceData.AREAS, so the spread view has "
		+ "nowhere to draw them. Add the folder to AREAS: %s" % str(homeless)
		).is_empty()


func test_every_priced_def_names_a_spendable_currency() -> void:
	var wrong: Array[String] = []
	for bucket: String in _priced_buckets():
		for path: String in _report[bucket]:
			var currency := String(_report[bucket][path].get("currency", ""))
			if not SPENDABLE.has(currency):
				wrong.append("%s -> %s" % [path, currency])
	assert_array(wrong).override_failure_message(
		"A currency has to be a PlayerData field UpgradeSystem.buy() can spend, or one of "
		+ "the two labels for what is not a currency. These are neither: %s" % str(wrong)
		).is_empty()


func test_every_priced_def_can_be_joined_to_a_purchase() -> void:
	var nameless: Array[String] = []
	for bucket: String in _priced_buckets():
		for path: String in _report[bucket]:
			if String(_report[bucket][path].get("id", "")).is_empty():
				nameless.append(path)
	assert_array(nameless).override_failure_message(
		"identity_of() found no id, key or node_id on these, so nothing joins their cost "
		+ "curve to what a simulated run recorded buying: %s" % str(nameless)
		).is_empty()

# ─── The biome lane is resolved, not guessed ─────────────────────────────────

func test_biome_upgrades_are_laned_by_upgrade_ids_and_not_by_folder() -> void:
	# The folders lag the renames: data/upgrades/biomes/forest holds the *meadow*
	# upgrades. Laning by folder name would put them under the wrong biome, and
	# every number read off that lane would be about a biome nobody was looking
	# at. Pinned by the mismatch itself, so a future rename that fixes the
	# folders is a test that still passes rather than one that breaks.
	var by_lane: Dictionary[String, String] = {}
	for path: String in _report["curves"]:
		var curve: Dictionary = _report["curves"][path]
		if curve.get("area", "") != "biome":
			continue
		by_lane[String(curve["sub_area"])] = path

	var keys: Array[String] = []
	for def: BiomeDef in (load("res://data/biomes/all_biomes.tres") as BiomeList).biomes:
		keys.append(String(def.key))

	for lane: String in by_lane:
		assert_array(keys).override_failure_message(
			"Biome upgrade lane \"%s\" (%s) is not a biome key. It was read off the folder "
			+ "name instead of BiomeDef.upgrade_ids." % [lane, by_lane[lane]]
			).contains([lane])


func test_meadow_owns_the_upgrades_filed_under_the_forest_folder() -> void:
	var curve: Dictionary = _report["curves"].get(
		"res://data/upgrades/biomes/forest/dense_mycelium_def.tres", {})
	assert_str(String(curve.get("sub_area", ""))).override_failure_message(
		"data/upgrades/biomes/forest holds DenseMycelium, which res_biome_meadow.tres lists "
		+ "in upgrade_ids. The lane has to follow the ids, not the folder."
		).is_equal("meadow")

# ─── helpers ─────────────────────────────────────────────────────────────────

## The buckets curves() fills with things that carry a price. `boons` are granted
## rather than bought and `achievements` are measured in goals, so neither has a
## currency to name.
func _priced_buckets() -> Array[String]:
	return ["curves", "boosts", "heroes", "workers", "fertilizer"]
