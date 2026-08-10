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
## key -> BiomeDef. Built once: biome_def() sits under the automation tick's
## inner loops, and the authored list never changes at runtime.
var _defs_by_key: Dictionary = {}

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
	for def in _biomes.biomes:
		_defs_by_key[def.key] = def

# ---------------------------------------------------------------- lookup

func biome_def(key: StringName) -> BiomeDef:
	return _defs_by_key.get(key)

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

## Opens the starter biomes, the only ones that cost nothing. Runs on a fresh
## game and again after every prestige reset.
##
## An armed auto-unlock is deliberately not honoured here: it buys the biome back
## rather than granting it, so AutomationSystem pays its nutrient price once the
## run can afford it.
func unlock_free_biomes() -> void:
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

# ---------------------------------------------------------------- auto-unlock

func has_auto_unlock(key: StringName) -> bool:
	return _biomes_data.is_auto_unlock(key)

func is_auto_unlock_enabled(key: StringName) -> bool:
	return _biomes_data.is_auto_unlock_enabled(key)

## Owned *and* switched on, which is the only combination that has the automation
## buy this biome back.
## The two are asked separately everywhere else, so the pairing lives here rather
## than being re-spelled at each call site.
func is_auto_unlock_armed(key: StringName) -> bool:
	return has_auto_unlock(key) and is_auto_unlock_enabled(key)

## Switching off is not a refund: the purchase stays owned, so it can be switched
## back on for free. Ignored for a biome that never bought one, which has no
## switch to throw.
func set_auto_unlock_enabled(key: StringName, value: bool) -> void:
	if not has_auto_unlock(key):
		return
	_biomes_data.set_auto_unlock_enabled(key, value)

func toggle_auto_unlock_enabled(key: StringName) -> void:
	set_auto_unlock_enabled(key, not is_auto_unlock_enabled(key))

func auto_unlock_cost(key: StringName) -> BigNumber:
	var def := biome_def(key)
	return def.auto_unlock_cost if def != null else BigNumber.new(0.0, 0)

## Pointless on a starter biome, which never relocks, and on one already bought.
func can_buy_auto_unlock(key: StringName) -> bool:
	var def := biome_def(key)
	if def == null or def.always_unlocked or has_auto_unlock(key):
		return false
	return _player_data.crystals.gte(def.auto_unlock_cost)

## Paid in crystals, and buys an auto-buyer rather than the biome itself: the
## biome stays shut until the run can afford its nutrient price, at which point
## AutomationSystem pays it. Applies to the current run as well as every later
## one, so a locked biome the player can already afford opens on the next tick.
func buy_auto_unlock(key: StringName) -> bool:
	if not can_buy_auto_unlock(key):
		return false
	# Flag first, pay second, and that order is load-bearing. The crystal
	# deduction reaches views too, and paying first makes it arrive while the flag
	# is still unset, so the section repaints still offering what was just bought.
	_biomes_data.set_auto_unlock(key)
	_player_data.crystals = _player_data.crystals.sub(auto_unlock_cost(key))
	return true

# ---------------------------------------------------------------- upgrades

func upgrade_ids(key: StringName) -> Array[StringName]:
	var def := biome_def(key)
	if def == null:
		return []
	return def.upgrade_ids

func upgrade_level(id: StringName) -> int:
	return _biome_upgrades.level(id)

## True once enough points are spent in this biome. Gates the later, stronger
## upgrades behind investment in the earlier ones.
func is_upgrade_unlocked(id: StringName, key: StringName) -> bool:
	var def := _biome_upgrades.def(id)
	return def != null and _biomes_data.points_spent(key) >= def.min_biome_points_spent

## Everything can_buy_upgrade() checks except whether a point is available: the
## upgrade's gate is met and it still has room to level.
##
## Split out because available_points() is by far the expensive half - it
## re-derives the biome's XP and resolves &"biome_points" through all three
## upgrade tracks - and a caller testing many upgrades against the same budget
## (the automation walking a recorded sequence) should pay for it once, not once
## per upgrade.
func has_upgrade_room(id: StringName, key: StringName) -> bool:
	if not is_upgrade_unlocked(id, key):
		return false
	var def := _biome_upgrades.def(id)
	return def != null and (def.max_level <= 0 or _biome_upgrades.level(id) < def.max_level)

func can_buy_upgrade(id: StringName, key: StringName) -> bool:
	return available_points(key) >= 1 and has_upgrade_room(id, key)

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
	var scaled_size := float(size(key)) * pow(def.size_cost_growth_exponent, float(size(key)))
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
	# Lifetime total, unlike BiomesData.size, which the prestige reset clears.
	_player_data.lifetime_biome_size += 1
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
	unlock_free_biomes()
