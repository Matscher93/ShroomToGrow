class_name PlayerData
extends RefCounted
## MODEL — pure state and game rules. Knows nothing about ViewModels or UI.
## Swap `float` for your BigNumber class where needed; the pattern is identical
## as long as BigNumber comparisons/emits go through the setters.

signal gold_changed(value: float)
signal upgrade_level_changed(level: int)

var gold: float = 0.0:
	set(value):
		if is_equal_approx(gold, value):
			return
		gold = value
		gold_changed.emit(gold)

var upgrade_level: int = 0:
	set(value):
		if upgrade_level == value:
			return
		upgrade_level = value
		upgrade_level_changed.emit(upgrade_level)

## Game rules live here (or in dedicated systems that mutate the model).
func upgrade_cost() -> float:
	return 10.0 * pow(1.15, upgrade_level)

func can_afford_upgrade() -> bool:
	return gold >= upgrade_cost()

func buy_upgrade() -> bool:
	if not can_afford_upgrade():
		return false
	gold -= upgrade_cost()
	upgrade_level += 1
	return true
