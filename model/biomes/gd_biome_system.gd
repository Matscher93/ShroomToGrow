class_name BiomeSystem
extends RefCounted
## MODEL: every rule about biomes. Unlocking, XP and levels, the point budget,
## the point-bought upgrades and Biome Size.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

var _biomes: BiomeList
var _biomes_data: BiomesData
var _player_data: PlayerData
var _mycelium_nodes: Array[MyceliumNode]
var _production: ProductionSystem
var _symbiosis: UpgradeSystem
var _biome_upgrades: UpgradeSystem
var _prestige_upgrades: UpgradeSystem
var _ctx: ResolveContext

func _init(biomes: BiomeList, biomes_data: BiomesData, player_data: PlayerData,
		mycelium_nodes: Array[MyceliumNode], production: ProductionSystem,
		symbiosis: UpgradeSystem, biome_upgrades: UpgradeSystem,
		prestige_upgrades: UpgradeSystem, ctx: ResolveContext) -> void:
	_biomes = biomes
	_biomes_data = biomes_data
	_player_data = player_data
	_mycelium_nodes = mycelium_nodes
	_production = production
	_symbiosis = symbiosis
	_biome_upgrades = biome_upgrades
	_prestige_upgrades = prestige_upgrades
	_ctx = ctx

# ---------------------------------------------------------------- lookup

func biome_def(key: StringName) -> BiomeDef:
	for def in _biomes.biomes:
		if def.key == key:
			return def
	return null

func biome_def_for_screen(screen_type: int) -> BiomeDef:
	for def in _biomes.biomes:
		if def.screen_type == screen_type:
			return def
	return null

## Gates bottom-bar tab visibility only. Once ever unlocked, a biome's screen
## stays reachable across prestige resets. Feature access inside that screen is
## gated separately on biomes_data.is_unlocked.
func is_screen_unlocked(screen_type: int) -> bool:
	if screen_type == ScreenTypes.Types.BIOMES:
		return true
	var def := biome_def_for_screen(screen_type)
	return def == null or _biomes_data.is_ever_unlocked(def.key)

func unlock_starting_biomes() -> void:
	for def in _biomes.biomes:
		if def.always_unlocked:
			_biomes_data.unlock(def.key)

# ---------------------------------------------------------------- xp / levels

func biome_xp(key: StringName) -> int:
	var def := biome_def(key)
	if def == null:
		return 0
	return BiomeCalculator.xp_for(def, _mycelium_nodes, _symbiosis, _player_data)

func biome_level(key: StringName) -> Dictionary:
	return BiomeCalculator.level_for(biome_xp(key))

## Level-derived points plus any flat bonus from upgrades in any track that
## target the &"biome_points" stat for this biome.
func available_points(key: StringName) -> int:
	var lvl: int = biome_level(key).level
	var base_points := lvl - 1
	var bonus := _production.stack(&"biome_points", BigNumber.new(0.0, 0), key)
	return max(0, base_points + int(bonus.to_float()) - _biomes_data.points_spent(key))

# ---------------------------------------------------------------- unlocking

func can_unlock(key: StringName) -> bool:
	var def := biome_def(key)
	if def == null or _biomes_data.is_unlocked(key):
		return false
	var currency: BigNumber = _player_data.get(CurrencyTypes.field_for(def.unlock_currency))
	return currency.gte(def.unlock_cost)

func unlock(key: StringName) -> bool:
	if not can_unlock(key):
		return false
	var def := biome_def(key)
	var field := CurrencyTypes.field_for(def.unlock_currency)
	var current: BigNumber = _player_data.get(field)
	_player_data.set(field, current.sub(def.unlock_cost))
	_biomes_data.unlock(key)
	return true

# ---------------------------------------------------------------- upgrades

func upgrade_ids(key: StringName) -> Array[StringName]:
	var def := biome_def(key)
	if def == null:
		return []
	return def.upgrade_ids

## True once enough points are spent in this biome. Gates the later, stronger
## upgrades behind investment in the earlier ones.
func is_upgrade_unlocked(id: StringName, key: StringName) -> bool:
	var def := _biome_upgrades.def(id)
	return def != null and _biomes_data.points_spent(key) >= def.min_biome_points_spent

func can_buy_upgrade(id: StringName, key: StringName) -> bool:
	if available_points(key) < 1:
		return false
	if not is_upgrade_unlocked(id, key):
		return false
	var def := _biome_upgrades.def(id)
	return def != null and (def.max_level <= 0 or _biome_upgrades.level(id) < def.max_level)

func buy_upgrade(id: StringName, key: StringName) -> bool:
	if not can_buy_upgrade(id, key):
		return false
	# Spend before buying: buy_with_points emits upgrades_changed synchronously
	# and views refresh points_spent() off that signal, so spending after would
	# show the pre-purchase count until something forced a second refresh.
	_biomes_data.spend_points(key, 1)
	if not _biome_upgrades.buy_with_points(id, true):
		_biomes_data.spend_points(key, -1)  # refund, def had no room left to level
		return false
	return true

# ---------------------------------------------------------------- biome size

func size(key: StringName) -> int:
	return _biomes_data.biome_size(key)

func size_cost(key: StringName) -> BigNumber:
	var def := biome_def(key)
	if def == null:
		return BigNumber.new(0.0, 0)
	var scaled_size := pow(float(size(key)), def.size_cost_growth_exponent)
	return def.size_base_cost.mul(BigNumber.from_value(def.size_cost_growth).pow_float(scaled_size))

func can_buy_size(key: StringName) -> bool:
	if biome_def(key) == null:
		return false
	return _player_data.nutrients.gte(size_cost(key))

## Caller announces the change (App re-emits biome_size_changed), since views
## bind to App rather than to this system.
func buy_size(key: StringName) -> bool:
	if not can_buy_size(key):
		return false
	_player_data.nutrients = _player_data.nutrients.sub(size_cost(key))
	_biomes_data.increase_size(key)
	_ctx.biome_sizes[key] = _biomes_data.biome_size(key)
	_symbiosis.invalidate()
	_biome_upgrades.invalidate()
	_prestige_upgrades.invalidate()
	return true

# ---------------------------------------------------------------- prestige

func reset() -> void:
	_biomes_data.reset()
	_ctx.biome_sizes.clear()
	# Same contract as buy_size: whoever writes _ctx invalidates every system
	# that caches a ScalingSourceDef reading it.
	_symbiosis.invalidate()
	_biome_upgrades.invalidate()
	_prestige_upgrades.invalidate()
	unlock_starting_biomes()
