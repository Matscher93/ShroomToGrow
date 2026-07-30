class_name PerkSystem
extends RefCounted
## MODEL — perk availability and purchase rules over the prestige upgrade track.
##
## The tree's shape lives in PerkTree (which generates the PerkDefs) and its
## levels live in the prestige UpgradeSystem; this only answers "can this be
## bought, and what does it cost". Holds no App reference.

const STATUS_OWNED := "owned"
const STATUS_AVAILABLE := "available"
const STATUS_LOCKED := "locked"

var _defs: Dictionary          # StringName -> PerkDef
var _upgrades: UpgradeSystem
var _player_data: PlayerData

func _init(defs: Dictionary, upgrades: UpgradeSystem, player_data: PlayerData) -> void:
	_defs = defs
	_upgrades = upgrades
	_player_data = player_data

func perk_def(id: StringName) -> PerkDef:
	return _defs.get(id)

## "owned" (level > 0), "available" (parent owned, this isn't maxed), or
## "locked" (parent not yet owned).
func status(id: StringName) -> String:
	var def := perk_def(id)
	if def == null:
		return STATUS_LOCKED
	if _upgrades.level(id) > 0:
		return STATUS_OWNED
	if def.parent_id == &"" or _upgrades.level(def.parent_id) > 0:
		return STATUS_AVAILABLE
	return STATUS_LOCKED

func can_buy(id: StringName) -> bool:
	if status(id) == STATUS_LOCKED:
		return false
	return _upgrades.can_buy(id, _player_data.biomass)

func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	return _upgrades.buy(id, _player_data, &"biomass")
