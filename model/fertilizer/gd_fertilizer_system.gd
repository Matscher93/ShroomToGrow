class_name FertilizerSystem
extends RefCounted
## MODEL: the fertilizer currency and the upgrades it buys.
##
## Thin by design - the ladder itself is an UpgradeSystem track like the boosts
## and the well projects, so cost, level and effect resolution are already handled
## there. What lives here is the currency: who may grant it, and that a purchase
## spends `fertilizer` rather than nutrients.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

## The PlayerData field a purchase spends. UpgradeSystem.buy() takes a field name
## rather than a CurrencyTypes value, which is why fertilizer needs no entry in
## that append-only, save-serialised enum.
const CURRENCY_FIELD := &"fertilizer"

var _player_data: PlayerData
var _upgrades: UpgradeSystem
var _list: FertilizerUpgradeList

func _init(player_data: PlayerData, upgrades: UpgradeSystem,
		list: FertilizerUpgradeList) -> void:
	_player_data = player_data
	_upgrades = upgrades
	_list = list

# ---------------------------------------------------------------- currency

## Pays fertilizer out, moving the lifetime total with it. The one entry point -
## events grant through here rather than writing the field, so no payout can
## reach the balance without also reaching the stat that measures it.
func grant(amount: BigNumber) -> void:
	if amount == null or amount.mantissa <= 0.0:
		return
	_player_data.fertilizer = _player_data.fertilizer.add(amount)
	_player_data.lifetime_fertilizer = _player_data.lifetime_fertilizer.add(amount)

func balance() -> BigNumber:
	return _player_data.fertilizer

# ---------------------------------------------------------------- upgrades

func upgrades() -> Array[FertilizerUpgradeDef]:
	if _list == null:
		return [] as Array[FertilizerUpgradeDef]
	return _list.upgrades

func level(id: StringName) -> int:
	return _upgrades.level(id)

func cost(id: StringName) -> BigNumber:
	return _upgrades.cost(id)

func can_buy(id: StringName) -> bool:
	return _upgrades.can_buy(id, _player_data.fertilizer)

func buy(id: StringName) -> bool:
	return _upgrades.buy(id, _player_data, CURRENCY_FIELD)

## The multiplier one upgrade currently applies, for the sheet's row. Its levels
## add rather than compound, matching the MORE + LINEAR shape FertilizerTree
## generates.
func multiplier(id: StringName) -> BigNumber:
	var def := _def(id)
	if def == null:
		return BigNumber.from_value(1.0)
	return BigNumber.from_value(1.0 + def.per_level * float(level(id)))

func _def(id: StringName) -> FertilizerUpgradeDef:
	for upgrade in upgrades():
		if upgrade != null and upgrade.id == id:
			return upgrade
	return null
