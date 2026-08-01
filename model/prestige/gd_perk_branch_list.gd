class_name PerkBranchList
extends Resource
## MODEL: ordered registry of every PerkBranchDef plus the core node they grow
## from, loaded once by App. Mirrors BiomeList / MyceliumNodes / Screens.

## Hue used by the core and any node with no branch of its own.
const CORE_HUE := 270.0

@export var core: PerkNodeDef
@export var branches: Array[PerkBranchDef]

func branch(key: StringName) -> PerkBranchDef:
	for b in branches:
		if b.key == key:
			return b
	return null

func hue_for(key: StringName) -> float:
	var b := branch(key)
	return b.hue if b != null else CORE_HUE
