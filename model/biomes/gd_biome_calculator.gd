class_name BiomeCalculator
extends RefCounted
## MODEL: pure calculation of biome XP and leveling. Performs no writes.
##
## Counters are passed in rather than read off the App autoload: autoloads don't
## exist outside a running game, so anything referencing App can't be compiled
## by a test harness.

## Sums manual_nodes only, not the auto-generated BigNumber tiers, so it always
## fits a plain int. "nodes grown" tracks purchases, not throughput.
static func xp_for(def: BiomeDef, mycelium_nodes: Array[MyceliumNode],
		symbiosis: UpgradeSystem, player_data: PlayerData) -> int:
	match def.xp_source:
		BiomeDef.XpSource.TOTAL_NODES:
			var total := 0
			for node in mycelium_nodes:
				total += node.manual_nodes
			return total
		BiomeDef.XpSource.SYMBIOSIS_LEVELS:
			return symbiosis.total_levels()
		BiomeDef.XpSource.PRESTIGE_COUNT:
			return player_data.prestige_count * 10
		BiomeDef.XpSource.ACHIEVEMENT_TIERS:
			return player_data.achievement_tiers
		_:
			return 0

## Level 1 starts at xp=0, each level needs floor(prev_need*1.55) more XP.
## Growth is exponential, so this loop stays short even at very high xp.
static func level_for(xp: int) -> Dictionary:
	var lvl := 1
	var need := 6
	var acc := 0
	while xp >= acc + need:
		acc += need
		lvl += 1
		need = int(round(need * 1.55))
	return {"level": lvl, "into": xp - acc, "need": need}
