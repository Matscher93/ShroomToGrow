extends GdUnitTestSuite
## Unit tests for PerkSystem (model/prestige/gd_perk_system.gd), driven by the
## real authored perk tree so the data and the rules are checked together.

var _player: PlayerData
var _upgrades: UpgradeSystem
var _defs: Dictionary
var _perks: PerkSystem

func before_test() -> void:
	var branches := load("res://data/prestige/all_branches.tres") as PerkBranchList
	_player = PlayerData.new()
	_upgrades = UpgradeSystem.new()
	_defs = {}
	for perk in PerkTree.build(branches):
		_upgrades.register(perk)
		_defs[perk.id] = perk
	_perks = PerkSystem.new(_defs, _upgrades, _player)

func _a_child_of_core() -> StringName:
	for id: StringName in _defs:
		if _defs[id].parent_id == &"core":
			return id
	return &""

func test_authored_tree_builds_more_than_the_core() -> void:
	assert_int(_defs.size()).is_greater(1)
	assert_object(_perks.perk_def(&"core")).is_not_null()

func test_every_authored_perk_id_is_unique_tree_wide() -> void:
	# Ids are the save keys, so two branches sharing one would collapse into a
	# single perk here rather than fail loudly at load time.
	var built := PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList)
	assert_int(_defs.size()).is_equal(built.size())

func test_core_is_available_from_the_start() -> void:
	assert_str(_perks.status(&"core")).is_equal(PerkSystem.STATUS_AVAILABLE)

func test_unknown_perk_is_locked() -> void:
	assert_str(_perks.status(&"NoSuchPerk")).is_equal(PerkSystem.STATUS_LOCKED)
	assert_bool(_perks.can_buy(&"NoSuchPerk")).is_false()
	assert_object(_perks.perk_def(&"NoSuchPerk")).is_null()

func test_child_is_locked_until_its_parent_is_owned() -> void:
	var child := _a_child_of_core()
	assert_str(child).is_not_empty()
	assert_str(_perks.status(child)).is_equal(PerkSystem.STATUS_LOCKED)
	assert_bool(_perks.can_buy(child)).is_false()

func test_buying_a_perk_unlocks_its_children() -> void:
	var child := _a_child_of_core()
	_player.biomass = BigNumber.from_value(1e12)

	assert_bool(_perks.can_buy(&"core")).is_true()
	assert_bool(_perks.buy(&"core")).is_true()
	assert_str(_perks.status(&"core")).is_equal(PerkSystem.STATUS_OWNED)
	assert_str(_perks.status(child)).is_equal(PerkSystem.STATUS_AVAILABLE)

func test_buying_spends_biomass_not_nutrients() -> void:
	_player.biomass = BigNumber.from_value(1e12)
	_player.nutrients = BigNumber.from_value(500.0)
	_perks.buy(&"core")

	assert_bool(_player.biomass.lt(BigNumber.from_value(1e12))).is_true()
	assert_float(_player.nutrients.to_float()).is_equal_approx(500.0, 0.001)

func test_cannot_buy_without_biomass() -> void:
	_player.biomass = BigNumber.from_value(0.0)
	assert_bool(_perks.can_buy(&"core")).is_false()
	assert_bool(_perks.buy(&"core")).is_false()
	assert_str(_perks.status(&"core")).is_equal(PerkSystem.STATUS_AVAILABLE)

func test_locked_perk_cannot_be_bought_even_with_biomass() -> void:
	_player.biomass = BigNumber.from_value(1e12)
	var child := _a_child_of_core()
	assert_bool(_perks.buy(child)).is_false()
	assert_int(_upgrades.level(child)).is_zero()
